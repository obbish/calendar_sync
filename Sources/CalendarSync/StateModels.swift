import Foundation

struct SyncState: Codable {
    var groups: [SyncGroup]
}

struct SyncGroup: Codable {
    let id: String
    var sourceCalendarId: String?
    var sourceEventId: String?
    var events: [EventReference]
}

struct EventReference: Codable {
    let calendarId: String
    let eventId: String
    var lastModified: Double
    var startDate: Double? // Optional for backward compatibility
    var isDeleted: Bool
}
