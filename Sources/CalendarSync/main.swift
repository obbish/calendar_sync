import Foundation
import EventKit

import Foundation
import EventKit

print("Calendar Mesh Sync Tool")

let manager = CalendarManager()

do {
    let authorized = try await manager.requestAccess()
    guard authorized else {
        print("Access denied.")
        exit(1)
    }
    
    let calendars = manager.getWritableCalendars()
    let configManager = ConfigManager()
    var selectedCalendars: [EKCalendar] = []

    if let config = configManager.load() {
        print("Running in Headless Mode using config.json")
        Logger.shared.log("Headless mode started")
        selectedCalendars = calendars.filter { config.selectedCalendarIds.contains($0.calendarIdentifier) }
        
        if selectedCalendars.isEmpty {
            print("No valid calendars found in config. Exiting.")
            Logger.shared.log("No valid calendars in config", level: "ERROR")
            exit(1)
        }
        print("Selected: \(selectedCalendars.map { $0.title }.joined(separator: ", "))")
    } else {
        print("\nAvailable Calendars:")
        for (index, calendar) in calendars.enumerated() {
            print("\(index + 1). \(calendar.title) (\(calendar.source.title))")
        }
        
        print("\nEnter comma-separated numbers of calendars to sync (e.g., 1,3):")
        guard let input = readLine() else { exit(0) }
        
        let indices = input.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        selectedCalendars = indices.compactMap { index in
            if index > 0 && index <= calendars.count {
                return calendars[index - 1]
            }
            return nil
        }
        
        if selectedCalendars.count < 2 {
            print("You must select at least 2 calendars.")
            exit(0)
        }
        
        print("Selected: \(selectedCalendars.map { $0.title }.joined(separator: ", "))")
        
        print("Do you want to save this selection for future automated runs? (y/n)")
        if let saveAns = readLine(), saveAns.lowercased() == "y" {
            let config = AppConfig(selectedCalendarIds: selectedCalendars.map { $0.calendarIdentifier })
            configManager.save(config)
            print("Configuration saved to config.json")
        }
    }
    
    let stateManager = StateManager()
    
    let engine = SyncEngine(calendarManager: manager, stateManager: stateManager, calendars: selectedCalendars)
    try await engine.sync()
    
} catch {
    print("Error: \(error)")
}

