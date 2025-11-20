import Foundation

class StateManager {
    private let stateFile = "calendar_state.json"
    private let backupDir = "backups"
    private var state: SyncState
    private let fileManager = FileManager.default
    
    init() {
        self.state = SyncState(groups: [])
        load()
    }
    
    private func load() {
        if fileManager.fileExists(atPath: stateFile) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: stateFile))
                state = try JSONDecoder().decode(SyncState.self, from: data)
                Logger.shared.log("State loaded", details: ["groups": state.groups.count])
            } catch {
                Logger.shared.log("Failed to load state", details: ["error": "\(error)"], level: "ERROR")
                // Start fresh if load fails? Or backup corrupt file?
                // For safety, let's backup the corrupt file if it exists
                try? fileManager.copyItem(atPath: stateFile, toPath: "\(stateFile).corrupt.\(Date().timeIntervalSince1970)")
                state = SyncState(groups: [])
            }
        } else {
            Logger.shared.log("No existing state file. Starting fresh.")
        }
    }
    
    func save() {
        do {
            // Create backup first
            if !fileManager.fileExists(atPath: backupDir) {
                try fileManager.createDirectory(atPath: backupDir, withIntermediateDirectories: true)
            }
            if fileManager.fileExists(atPath: stateFile) {
                let backupPath = "\(backupDir)/state_backup_\(Int(Date().timeIntervalSince1970)).json"
                try fileManager.copyItem(atPath: stateFile, toPath: backupPath)
            }
            
            let data = try JSONEncoder().encode(state)
            try data.write(to: URL(fileURLWithPath: stateFile))
            Logger.shared.log("State saved")
        } catch {
            Logger.shared.log("Failed to save state", details: ["error": "\(error)"], level: "ERROR")
        }
    }
    
    // MARK: - Accessors
    
    func getEventState(calendarId: String, eventId: String) -> (group: SyncGroup, ref: EventReference)? {
        for group in state.groups {
            if let ref = group.events.first(where: { $0.calendarId == calendarId && $0.eventId == eventId }) {
                return (group, ref)
            }
        }
        return nil
    }
    
    func updateEventState(calendarId: String, eventId: String, lastModified: Double, startDate: Double, syncGroupId: String) {
        // Find if event exists in any group
        if let (existingGroup, _) = getEventState(calendarId: calendarId, eventId: eventId) {
            // Update existing ref
            if let index = state.groups.firstIndex(where: { $0.id == existingGroup.id }) {
                if let refIndex = state.groups[index].events.firstIndex(where: { $0.calendarId == calendarId && $0.eventId == eventId }) {
                    state.groups[index].events[refIndex].lastModified = lastModified
                    state.groups[index].events[refIndex].startDate = startDate
                    state.groups[index].events[refIndex].isDeleted = false // Resurrect if it was deleted
                }
            }
        } else {
            // New event state
            let newRef = EventReference(calendarId: calendarId, eventId: eventId, lastModified: lastModified, startDate: startDate, isDeleted: false)
            
            if let index = state.groups.firstIndex(where: { $0.id == syncGroupId }) {
                // Add to existing group
                state.groups[index].events.append(newRef)
            } else {
                // Create new group
                let newGroup = SyncGroup(id: syncGroupId, sourceCalendarId: nil, sourceEventId: nil, events: [newRef])
                state.groups.append(newGroup)
            }
        }
    }
    
    func pruneEvents(olderThan date: Date) {
        let threshold = date.timeIntervalSince1970
        var prunedCount = 0
        
        // Filter out events that are older than threshold
        // We keep groups that still have valid events
        
        for i in 0..<state.groups.count {
            state.groups[i].events.removeAll { ref in
                if let start = ref.startDate {
                    if start < threshold {
                        prunedCount += 1
                        return true
                    }
                }
                return false
            }
        }
        
        // Remove empty groups
        state.groups.removeAll { $0.events.isEmpty }
        
        if prunedCount > 0 {
            Logger.shared.log("Pruned old events", details: ["count": prunedCount, "threshold": date])
        }
    }
    
    func markAsDeleted(calendarId: String, eventId: String) {
        if let (group, _) = getEventState(calendarId: calendarId, eventId: eventId) {
            if let index = state.groups.firstIndex(where: { $0.id == group.id }) {
                if let refIndex = state.groups[index].events.firstIndex(where: { $0.calendarId == calendarId && $0.eventId == eventId }) {
                    state.groups[index].events[refIndex].isDeleted = true
                    Logger.shared.log("Marked event as deleted", details: ["calendarId": calendarId, "eventId": eventId])
                }
            }
        }
    }
    
    func getSyncGroup(syncGroupId: String) -> SyncGroup? {
        return state.groups.first(where: { $0.id == syncGroupId })
    }
    
    func getAllTrackedEvents(calendarIds: [String]) -> [EventReference] {
        var refs: [EventReference] = []
        for group in state.groups {
            for ref in group.events {
                if calendarIds.contains(ref.calendarId) && !ref.isDeleted {
                    refs.append(ref)
                }
            }
        }
        return refs
    }
    
    func mergeGroups(sourceGroupId: String, targetGroupId: String) {
        guard let sourceIndex = state.groups.firstIndex(where: { $0.id == sourceGroupId }),
              let targetIndex = state.groups.firstIndex(where: { $0.id == targetGroupId }) else { return }
        
        let sourceEvents = state.groups[sourceIndex].events
        state.groups[targetIndex].events.append(contentsOf: sourceEvents)
        state.groups.remove(at: sourceIndex)
        
        Logger.shared.log("Merged groups", details: ["source": sourceGroupId, "target": targetGroupId])
    }
    
    func setSource(syncGroupId: String, calendarId: String, eventId: String) {
        if let index = state.groups.firstIndex(where: { $0.id == syncGroupId }) {
            state.groups[index].sourceCalendarId = calendarId
            state.groups[index].sourceEventId = eventId
            Logger.shared.log("Set source for group", details: ["groupId": syncGroupId, "sourceCal": calendarId])
        }
    }
}
