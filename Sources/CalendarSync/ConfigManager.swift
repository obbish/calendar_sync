import Foundation

struct AppConfig: Codable {
    var selectedCalendarIds: [String]
}

class ConfigManager {
    private let fileManager = FileManager.default
    
    private var configFileURL: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".calendarsync")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }
    
    func load() -> AppConfig? {
        let url = configFileURL
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            Logger.shared.log("Failed to load config", details: ["error": "\(error)"], level: "ERROR")
            return nil
        }
    }
    
    func save(_ config: AppConfig) {
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: configFileURL)
            Logger.shared.log("Config saved", details: ["path": configFileURL.path])
        } catch {
            Logger.shared.log("Failed to save config", details: ["error": "\(error)"], level: "ERROR")
        }
    }
}
