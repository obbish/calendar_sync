import Foundation
import EventKit

class SyncEngine {
    private let calendarManager: CalendarManager
    private let stateManager: StateManager
    private let calendars: [EKCalendar]
    
    init(calendarManager: CalendarManager, stateManager: StateManager, calendars: [EKCalendar]) {
        self.calendarManager = calendarManager
        self.stateManager = stateManager
        self.calendars = calendars
    }
    
    func sync() async throws {
        Logger.shared.log("Starting sync", details: ["calendars": calendars.map { $0.title }])
        
        // 1. Fetch all events from all selected calendars
        // Window: -1 month to +1 year
        let startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        let endDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!
        
        var allEvents: [EKEvent] = []
        for calendar in calendars {
            let events = calendarManager.getEvents(from: [calendar], start: startDate, end: endDate)
            allEvents.append(contentsOf: events)
        }
        
        Logger.shared.log("Fetched events", details: ["count": allEvents.count])
        
        // 2. Process events
        // We need to track which events we've processed to handle deletions later
        var processedEventIds = Set<String>()
        
        for event in allEvents {
            processedEventIds.insert(event.eventIdentifier)
            try processEvent(event, processedEventIds: &processedEventIds)
        }
        
        // 3. Handle deletions
        // Check DB for events that should exist but don't
        let trackedEvents = stateManager.getAllTrackedEvents(calendarIds: calendars.map { $0.calendarIdentifier })
        
        for ref in trackedEvents {
            if !processedEventIds.contains(ref.eventId) {
                // Event was deleted from source
                // Find the group ID for this event
                if let (group, _) = stateManager.getEventState(calendarId: ref.calendarId, eventId: ref.eventId) {
                    Logger.shared.log("Event deleted from source", details: ["calendar": ref.calendarId, "event": ref.eventId])
                    try propagateDeletion(syncGroupId: group.id)
                }
            }
        }
        
        // 4. Pruning
        // Prune events and logs older than 1 month
        if let pruneDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) {
            stateManager.pruneEvents(olderThan: pruneDate)
            Logger.shared.pruneLogs(olderThan: pruneDate)
        }
        
        stateManager.save()
        Logger.shared.log("Sync complete")
    }
    
    private func propagateDeletion(syncGroupId: String) throws {
        guard let group = stateManager.getSyncGroup(syncGroupId: syncGroupId) else { return }
        
        // Self-healing logic:
        // 1. Identify valid events in this group.
        // 2. For each valid event, try to find a match in the calendars where the event is MISSING.
        
        var validEvents: [EKEvent] = []
        var missingRefs: [EventReference] = []
        
        for ref in group.events {
            if ref.isDeleted { continue } // Skip already deleted
            
            if let event = calendarManager.getEvent(identifier: ref.eventId) {
                validEvents.append(event)
            } else {
                missingRefs.append(ref)
            }
        }
        
        if validEvents.isEmpty {
            // All gone, just mark as deleted in State
            for ref in group.events {
                stateManager.markAsDeleted(calendarId: ref.calendarId, eventId: ref.eventId)
            }
            return
        }
        
        // We have at least one valid event. Use the first one as the "Source of Truth" to find matches.
        let sourceEvent = validEvents[0]
        
        for ref in missingRefs {
            guard let targetCalendar = calendars.first(where: { $0.calendarIdentifier == ref.calendarId }) else {
                // Calendar not selected, just mark deleted
                stateManager.markAsDeleted(calendarId: ref.calendarId, eventId: ref.eventId)
                continue
            }
            
            Logger.shared.log("Checking for replacement", details: ["target": targetCalendar.title, "missingEvent": ref.eventId])
            
            let searchStart = sourceEvent.startDate.addingTimeInterval(-86400)
            let searchEnd = sourceEvent.startDate.addingTimeInterval(86400)
            let candidates = calendarManager.getEvents(from: [targetCalendar], start: searchStart, end: searchEnd)
            
            if let match = candidates.first(where: {
                let titleMatch = ($0.title?.trimmingCharacters(in: .whitespacesAndNewlines) == sourceEvent.title?.trimmingCharacters(in: .whitespacesAndNewlines))
                let timeMatch = abs($0.startDate.timeIntervalSince(sourceEvent.startDate)) < 300
                return titleMatch && timeMatch
            }) {
                Logger.shared.log("Found replacement", details: ["match": match.title ?? "nil"])
                
                // Check if this match is already tracked in ANOTHER group
                if let (existingGroup, _) = stateManager.getEventState(calendarId: targetCalendar.calendarIdentifier, eventId: match.eventIdentifier) {
                    if existingGroup.id != syncGroupId {
                        Logger.shared.log("Merging groups", details: ["from": existingGroup.id, "to": syncGroupId])
                        stateManager.mergeGroups(sourceGroupId: existingGroup.id, targetGroupId: syncGroupId)
                        
                        // Mark the missing ref as deleted (replaced by the merged one)
                        stateManager.markAsDeleted(calendarId: ref.calendarId, eventId: ref.eventId)
                    }
                } else {
                    // Not tracked. Add to current group.
                    let lastModified = match.lastModifiedDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
                    let startDate = match.startDate.timeIntervalSince1970
                    stateManager.updateEventState(calendarId: targetCalendar.calendarIdentifier, eventId: match.eventIdentifier, lastModified: lastModified, startDate: startDate, syncGroupId: syncGroupId)
                    
                    // Mark old ref as deleted
                    stateManager.markAsDeleted(calendarId: ref.calendarId, eventId: ref.eventId)
                }
            } else {
                // No match found.
                // DECISION TIME: Did we lose the Source or a Copy?
                
                // Check if the Source is among the valid events
                let sourceExists = validEvents.contains(where: { 
                    $0.calendar.calendarIdentifier == group.sourceCalendarId && 
                    $0.eventIdentifier == group.sourceEventId 
                })
                
                if sourceExists {
                    // The Source still exists. The missing event was a COPY.
                    // We must NOT delete the Source.
                    // Instead, we should RESURRECT the copy to maintain the mesh.
                    // (Or we could ignore it, but "Sync" implies keeping them matching).
                    
                    Logger.shared.log("Copy deleted. Resurrecting.", details: ["missingIn": targetCalendar.title])
                    
                    // Find the source event object to copy from
                    if let sourceEvent = validEvents.first(where: { $0.calendar.calendarIdentifier == group.sourceCalendarId && $0.eventIdentifier == group.sourceEventId }) {
                        let newEvent = calendarManager.createEvent(in: targetCalendar)
                        copyEventData(from: sourceEvent, to: newEvent)
                        try calendarManager.save(event: newEvent)
                        
                        // Update state with new ID
                        let lastModified = newEvent.lastModifiedDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
                        let startDate = newEvent.startDate.timeIntervalSince1970
                        stateManager.updateEventState(calendarId: targetCalendar.calendarIdentifier, eventId: newEvent.eventIdentifier, lastModified: lastModified, startDate: startDate, syncGroupId: syncGroupId)
                        
                        // Mark the old missing ID as deleted (replaced by new one)
                        stateManager.markAsDeleted(calendarId: ref.calendarId, eventId: ref.eventId)
                    }
                } else {
                    // The Source is NOT among the valid events.
                    // This means the Source was deleted (or we have no source defined).
                    // If Source is gone, we should delete the copies.
                    
                    Logger.shared.log("Source deleted (or undefined). Propagating deletion.", details: ["group": syncGroupId])
                    stateManager.markAsDeleted(calendarId: ref.calendarId, eventId: ref.eventId)
                    
                    for event in validEvents {
                        Logger.shared.log("Deleting copy", details: ["calendar": event.calendar.title])
                        try calendarManager.remove(event: event)
                        stateManager.markAsDeleted(calendarId: event.calendar.calendarIdentifier, eventId: event.eventIdentifier)
                    }
                    // We deleted all valid events, so we can stop processing this group.
                    return
                }
            }
        }
    }
    
    private func processEvent(_ event: EKEvent, processedEventIds: inout Set<String>) throws {
        let calendarId = event.calendar.calendarIdentifier
        let eventId = event.eventIdentifier!
        let lastModified = event.lastModifiedDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
        let startDate = event.startDate.timeIntervalSince1970
        
        // Check if we know this event
        if let (group, ref) = stateManager.getEventState(calendarId: calendarId, eventId: eventId) {
            // Known event. Check for updates.
            if lastModified > ref.lastModified {
                Logger.shared.log("Event updated", details: ["title": event.title ?? "nil"])
                
                // Source Protection: If this event is NOT the source, but it was modified, 
                // strictly speaking we should revert it or ignore it if we want "One-Way Sync".
                // However, the requirement says "The program shall never update the true source".
                // It doesn't explicitly say we must revert changes to copies.
                // But usually "One-Way Sync" implies changes flow Source -> Copy.
                // If a Copy is changed, should it flow back? User said "never update the true source".
                // So we should NOT propagate changes FROM a copy TO the source.
                // But can we propagate changes FROM a copy TO OTHER copies?
                // Let's assume for now:
                // 1. If Source is updated -> Propagate to ALL copies.
                // 2. If Copy is updated -> Do NOT propagate to Source. (Maybe propagate to other copies? Or just ignore?)
                // For safety/simplicity based on "never update true source":
                // We will only propagate if the updated event IS the source (or if no source is defined yet).
                
                let isSource = (group.sourceCalendarId == calendarId && group.sourceEventId == eventId)
                let noSourceDefined = (group.sourceCalendarId == nil)
                
                if isSource || noSourceDefined {
                    try propagateUpdate(event, syncGroupId: group.id)
                    stateManager.updateEventState(calendarId: calendarId, eventId: eventId, lastModified: lastModified, startDate: startDate, syncGroupId: group.id)
                } else {
                    Logger.shared.log("Skipping propagation from copy", details: ["event": event.title ?? "nil"])
                    // We still update the state so we don't keep seeing it as "modified" every run
                    stateManager.updateEventState(calendarId: calendarId, eventId: eventId, lastModified: lastModified, startDate: startDate, syncGroupId: group.id)
                }
            }
        } else {
            // New event.
            let syncGroupId = UUID().uuidString
            Logger.shared.log("New event found", details: ["title": event.title ?? "nil", "groupId": syncGroupId])
            
            // Set this as the source
            stateManager.updateEventState(calendarId: calendarId, eventId: eventId, lastModified: lastModified, startDate: startDate, syncGroupId: syncGroupId)
            
            // We need to update the group to set the source
            if var group = stateManager.getSyncGroup(syncGroupId: syncGroupId) {
                group.sourceCalendarId = calendarId
                group.sourceEventId = eventId
                // We need a way to save this group update back to stateManager.
                // StateManager.updateEventState doesn't expose group properties.
                // We need a new method in StateManager or direct access.
                // Let's add `setSource` to StateManager.
                stateManager.setSource(syncGroupId: syncGroupId, calendarId: calendarId, eventId: eventId)
            }
            
            try propagateNewEvent(event, syncGroupId: syncGroupId, sourceCalendarId: calendarId, processedEventIds: &processedEventIds)
        }
    }
    
    private func propagateUpdate(_ sourceEvent: EKEvent, syncGroupId: String) throws {
        guard let group = stateManager.getSyncGroup(syncGroupId: syncGroupId) else { return }
        
        for ref in group.events {
            if ref.calendarId == sourceEvent.calendar.calendarIdentifier && ref.eventId == sourceEvent.eventIdentifier {
                continue
            }
            if ref.isDeleted { continue }
            
            // Source Protection: NEVER update the source.
            if let srcCal = group.sourceCalendarId, let srcEvt = group.sourceEventId {
                if ref.calendarId == srcCal && ref.eventId == srcEvt {
                    continue
                }
            }
            
            guard let targetEvent = calendarManager.getEvent(identifier: ref.eventId) else {
                Logger.shared.log("Target event not found during update", details: ["eventId": ref.eventId], level: "WARN")
                continue
            }
            
            Logger.shared.log("Updating target event", details: ["calendar": targetEvent.calendar.title])
            copyEventData(from: sourceEvent, to: targetEvent)
            try calendarManager.save(event: targetEvent)
            
            let lastModified = targetEvent.lastModifiedDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
            let startDate = targetEvent.startDate.timeIntervalSince1970
            stateManager.updateEventState(calendarId: ref.calendarId, eventId: ref.eventId, lastModified: lastModified, startDate: startDate, syncGroupId: syncGroupId)
        }
    }
    
    private func propagateNewEvent(_ sourceEvent: EKEvent, syncGroupId: String, sourceCalendarId: String, processedEventIds: inout Set<String>) throws {
        for targetCalendar in calendars {
            if targetCalendar.calendarIdentifier == sourceCalendarId { continue }
            
            // Fuzzy Matching
            let searchStart = sourceEvent.startDate.addingTimeInterval(-86400)
            let searchEnd = sourceEvent.startDate.addingTimeInterval(86400)
            
            let candidates = calendarManager.getEvents(from: [targetCalendar], start: searchStart, end: searchEnd)
            
            if let match = candidates.first(where: {
                let titleMatch = ($0.title?.trimmingCharacters(in: .whitespacesAndNewlines) == sourceEvent.title?.trimmingCharacters(in: .whitespacesAndNewlines))
                let timeMatch = abs($0.startDate.timeIntervalSince(sourceEvent.startDate)) < 300
                return titleMatch && timeMatch
            }) {
                Logger.shared.log("Found matching event", details: ["calendar": targetCalendar.title])
                let lastModified = match.lastModifiedDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
                let startDate = match.startDate.timeIntervalSince1970
                stateManager.updateEventState(calendarId: targetCalendar.calendarIdentifier, eventId: match.eventIdentifier, lastModified: lastModified, startDate: startDate, syncGroupId: syncGroupId)
                
                processedEventIds.insert(match.eventIdentifier)
                continue
            }
            
            Logger.shared.log("Replicating event", details: ["target": targetCalendar.title])
            let newEvent = calendarManager.createEvent(in: targetCalendar)
            copyEventData(from: sourceEvent, to: newEvent)
            
            try calendarManager.save(event: newEvent)
            
            processedEventIds.insert(newEvent.eventIdentifier)
            
            let lastModified = newEvent.lastModifiedDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
            let startDate = newEvent.startDate.timeIntervalSince1970
            stateManager.updateEventState(calendarId: targetCalendar.calendarIdentifier, eventId: newEvent.eventIdentifier, lastModified: lastModified, startDate: startDate, syncGroupId: syncGroupId)
        }
    }
    
    private func copyEventData(from source: EKEvent, to target: EKEvent) {
        target.title = source.title
        target.startDate = source.startDate
        target.endDate = source.endDate
        target.isAllDay = source.isAllDay
        target.location = source.location
        target.url = source.url
        
        // Metadata Injection
        var notes = source.notes ?? ""
        notes += "\n\n--- Sync Metadata ---"
        notes += "\nSource: \(source.calendar.title)"
        
        if let attendees = source.attendees, !attendees.isEmpty {
            notes += "\nParticipants:"
            for attendee in attendees {
                let status: String
                switch attendee.participantStatus {
                case .accepted: status = "Accepted"
                case .declined: status = "Declined"
                case .tentative: status = "Tentative"
                case .pending: status = "Pending"
                default: status = "Unknown"
                }
                notes += "\n- \(attendee.name ?? "Unknown") (\(status))"
            }
        }
        
        target.notes = notes
    }
}
