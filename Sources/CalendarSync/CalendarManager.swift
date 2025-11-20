import Foundation
import EventKit

class CalendarManager {
    private let store = EKEventStore()
    
    func requestAccess() async throws -> Bool {
        if #available(macOS 14.0, *) {
            return try await store.requestFullAccessToEvents()
        } else {
            return try await store.requestAccess(to: .event)
        }
    }
    
    func getWritableCalendars() -> [EKCalendar] {
        return store.calendars(for: .event).filter { $0.allowsContentModifications }
    }
    
    func getEvents(from calendars: [EKCalendar], start: Date, end: Date) -> [EKEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
    }
    
    func save(event: EKEvent, span: EKSpan = .thisEvent) throws {
        try store.save(event, span: span, commit: true)
    }
    
    func remove(event: EKEvent, span: EKSpan = .thisEvent) throws {
        try store.remove(event, span: span, commit: true)
    }
    
    func createEvent(in calendar: EKCalendar) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        return event
    }
    
    func getCalendar(withIdentifier identifier: String) -> EKCalendar? {
        return store.calendar(withIdentifier: identifier)
    }
    
    func getEvent(identifier: String) -> EKEvent? {
        return store.event(withIdentifier: identifier)
    }
}
