import EventKit

let eventStore = EKEventStore()

// List of source calendar names and the target calendar name
let sourceCalendarNames = ["Kalender", "Helgdagar i Sverige"]
let targetCalendarName = "Modermodemet"

// Sync options: set these to true to use custom values, false to sync actual event fields
let useCustomTitle = false
let useCustomLocation = false
let useCustomNotes = false

// Custom values if the above options are set to true
let customTitle = ""
let customLocation = ""
let customNotes = ""

// Check calendar access authorization status and request access if needed
switch EKEventStore.authorizationStatus(for: .event) {
case .notDetermined:
    print("Permission not determined. Requesting access...")
    eventStore.requestFullAccessToEvents { (granted, error) in
        if granted {
            print("Access granted.")
            syncCalendars(eventStore: eventStore)
        } else {
            print("Access denied: \(String(describing: error?.localizedDescription))")
        }
    }
case .authorized, .fullAccess:
    print("Access already authorized.")
    syncCalendars(eventStore: eventStore)
case .restricted, .denied:
    print("Access restricted or denied.")
case .writeOnly:
    print("Write-only access granted.")
@unknown default:
    print("Unknown permission status.")
}

// Function to sync events from source calendars to the target calendar
func syncCalendars(eventStore: EKEventStore) {
    let calendars = eventStore.calendars(for: .event)
    
    // Ensure target calendar exists
    guard let targetCalendar = calendars.first(where: { $0.title == targetCalendarName }) else {
        print("Target calendar '\(targetCalendarName)' not found.")
        return
    }
    
    // Find the source calendars
    let sourceCalendars = calendars.filter { sourceCalendarNames.contains($0.title) }
    guard !sourceCalendars.isEmpty else {
        print("No source calendars found.")
        return
    }
    
    // Define date range for events (180 days back and forward)
    let startDate = Calendar.current.date(byAdding: .day, value: -180, to: Date())!
    let endDate = Calendar.current.date(byAdding: .day, value: 180, to: Date())!
    
    // Fetch events from source calendars
    var allSourceEvents: [EKEvent] = []
    for calendar in sourceCalendars {
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: [calendar])
        allSourceEvents.append(contentsOf: eventStore.events(matching: predicate))
    }
    
    // Fetch events from the target calendar
    let targetPredicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: [targetCalendar])
    let targetEvents = eventStore.events(matching: targetPredicate)
    
    // Sync each event from the source calendars
    for sourceEvent in allSourceEvents {
        let sourceTitle = useCustomTitle ? customTitle : sourceEvent.title ?? "No Title"
        let sourceLocation = useCustomLocation ? customLocation : sourceEvent.location ?? ""
        let sourceNotes = useCustomNotes ? customNotes : sourceEvent.notes ?? ""
        
        // Check if event exists in the target calendar (by eventIdentifier first, then by start/end time)
        if let matchingEvent = targetEvents.first(where: { $0.eventIdentifier == sourceEvent.eventIdentifier }) {
            updateEvent(matchingEvent, title: sourceTitle, location: sourceLocation, notes: sourceNotes)
        } else if let matchingEventByTime = targetEvents.first(where: { $0.startDate == sourceEvent.startDate && $0.endDate == sourceEvent.endDate }) {
            updateEvent(matchingEventByTime, title: sourceTitle, location: sourceLocation, notes: sourceNotes)
        } else {
            createEvent(eventStore: eventStore, sourceEvent: sourceEvent, targetCalendar: targetCalendar, title: sourceTitle, location: sourceLocation, notes: sourceNotes)
        }
    }
    
    // Delete target events that no longer exist in source calendars
    deleteObsoleteEvents(allSourceEvents: allSourceEvents, targetEvents: targetEvents, eventStore: eventStore)
}

// Function to create a new event in the target calendar
func createEvent(eventStore: EKEventStore, sourceEvent: EKEvent, targetCalendar: EKCalendar, title: String, location: String, notes: String) {
    let newEvent = EKEvent(eventStore: eventStore)
    newEvent.title = title
    newEvent.startDate = sourceEvent.startDate
    newEvent.endDate = sourceEvent.endDate
    newEvent.location = location
    newEvent.notes = notes
    newEvent.calendar = targetCalendar
    
    do {
        try eventStore.save(newEvent, span: .thisEvent, commit: true)
        print("Created new event: \(title)")
    } catch {
        print("Error creating event: \(error.localizedDescription)")
    }
}

// Function to update an existing event in the target calendar
func updateEvent(_ event: EKEvent, title: String, location: String, notes: String) {
    event.title = title
    event.location = location
    event.notes = notes
    
    do {
        try eventStore.save(event, span: .thisEvent, commit: true)
        print("Updated event: \(title)")
    } catch {
        print("Error updating event: \(error.localizedDescription)")
    }
}

// Function to delete events in the target calendar that no longer exist in the source calendars
func deleteObsoleteEvents(allSourceEvents: [EKEvent], targetEvents: [EKEvent], eventStore: EKEventStore) {
    for targetEvent in targetEvents {
        let matchingSourceEvent = allSourceEvents.first { $0.eventIdentifier == targetEvent.eventIdentifier || ($0.startDate == targetEvent.startDate && $0.endDate == targetEvent.endDate) }
        
        if matchingSourceEvent == nil {
            do {
                try eventStore.remove(targetEvent, span: .thisEvent, commit: true)
                print("Deleted obsolete event: \(targetEvent.title ?? "Unnamed Event")")
            } catch {
                print("Error deleting event: \(error.localizedDescription)")
            }
        }
    }
}
