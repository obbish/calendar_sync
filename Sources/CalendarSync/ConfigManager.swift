import Foundation

struct AppConfig: Codable {
    var selectedCalendarIds: [String]
}

class ConfigManager {
    private let configFile = "config.json"
    private let fileManager = FileManager.default
    
    func load() -> AppConfig? {
        guard fileManager.fileExists(atPath: configFile) else { return nil }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: configFile))
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            Logger.shared.log("Failed to load config", details: ["error": "\(error)"], level: "ERROR")
            return nil
        }
    }
    
    func save(_ config: AppConfig) {
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: URL(fileURLWithPath: configFile))
            Logger.shared.log("Config saved")
        } catch {
            Logger.shared.log("Failed to save config", details: ["error": "\(error)"], level: "ERROR")
        }
    }
}
