import Foundation

class Logger {
    static let shared = Logger()
    private let logFile = "sync_log.json"
    private let fileManager = FileManager.default
    
    private init() {
        // Create log file if it doesn't exist, or append to it?
        // For structured JSON logs, it's often better to have one JSON object per line (JSONL)
        // or a big array. JSONL is safer for appending.
        if !fileManager.fileExists(atPath: logFile) {
            fileManager.createFile(atPath: logFile, contents: nil)
        }
    }
    
    func log(_ action: String, details: [String: Any] = [:], level: String = "INFO") {
        var logEntry: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "level": level,
            "action": action
        ]
        
        for (key, value) in details {
            logEntry[key] = value
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: logEntry, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let line = jsonString + "\n"
                if let data = line.data(using: .utf8) {
                    if let fileHandle = FileHandle(forWritingAtPath: logFile) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        fileHandle.closeFile()
                    }
                }
            }
            
            // Also print to console for immediate feedback
            print("[\(level)] \(action): \(details)")
        } catch {
            print("Failed to log: \(error)")
        }
    }
    
    func pruneLogs(olderThan date: Date) {
        // Read file, filter lines, rewrite file
        guard fileManager.fileExists(atPath: logFile) else { return }
        
        do {
            let content = try String(contentsOfFile: logFile, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            var keptLines: [String] = []
            let threshold = ISO8601DateFormatter().string(from: date)
            
            for line in lines {
                if line.isEmpty { continue }
                // Simple string comparison for ISO8601 works
                if let timestampRange = line.range(of: "\"timestamp\":\"") {
                    let afterTimestamp = line[timestampRange.upperBound...]
                    if let quoteIndex = afterTimestamp.firstIndex(of: "\"") {
                        let timestamp = String(afterTimestamp[..<quoteIndex])
                        if timestamp >= threshold {
                            keptLines.append(line)
                        }
                    }
                }
            }
            
            let newContent = keptLines.joined(separator: "\n") + "\n"
            try newContent.write(toFile: logFile, atomically: true, encoding: .utf8)
            
        } catch {
            print("Failed to prune logs: \(error)")
        }
    }
}
