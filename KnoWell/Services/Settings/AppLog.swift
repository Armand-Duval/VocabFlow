import Foundation
import os

/// Lightweight file logger. Writes under Documents/Logs so files are visible in
/// Files → On My iPhone → KnoWell → Logs (requires UIFileSharingEnabled).
enum AppLog {
    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
    }

    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.knowell.app1"
    private static let keepDays = 14
    private static let queue = DispatchQueue(label: "com.knowell.app1.applog", qos: .utility)
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let osLog = Logger(subsystem: subsystem, category: "App")

    // MARK: - Public API

    static func debug(_ message: String, category: String = "App", file: String = #fileID, line: Int = #line) {
        #if DEBUG
        write(.debug, category: category, message: message, file: file, line: line)
        #endif
    }

    static func info(_ message: String, category: String = "App", file: String = #fileID, line: Int = #line) {
        write(.info, category: category, message: message, file: file, line: line)
    }

    static func warn(_ message: String, category: String = "App", file: String = #fileID, line: Int = #line) {
        write(.warn, category: category, message: message, file: file, line: line)
    }

    static func error(_ message: String, category: String = "App", file: String = #fileID, line: Int = #line) {
        write(.error, category: category, message: message, file: file, line: line)
    }

    /// Call once at launch: ensure folder exists, prune old files, write a boot line.
    static func bootstrap() {
        queue.async {
            do {
                let folder = try logsDirectory()
                try pruneOldLogs(in: folder, keepingDays: keepDays)
                appendUnlocked(
                    level: .info,
                    category: "Lifecycle",
                    message: "AppLog ready → \(folder.path)",
                    file: #fileID,
                    line: #line
                )
            } catch {
                osLog.error("AppLog bootstrap failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static var logsFolderURL: URL? {
        try? logsDirectory()
    }

    // MARK: - Internals

    private static func write(
        _ level: Level,
        category: String,
        message: String,
        file: String,
        line: Int
    ) {
        mirrorToOSLog(level, category: category, message: message)
        queue.async {
            appendUnlocked(level: level, category: category, message: message, file: file, line: line)
        }
    }

    private static func appendUnlocked(
        level: Level,
        category: String,
        message: String,
        file: String,
        line: Int
    ) {
        do {
            let folder = try logsDirectory()
            let url = folder.appendingPathComponent(logFileName(for: .now))
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            let shortFile = file.split(separator: "/").last.map(String.init) ?? file
            let lineText = "\(isoFormatter.string(from: .now)) [\(level.rawValue)] [\(category)] \(message) (\(shortFile):\(line))\n"
            if let data = lineText.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } catch {
            osLog.error("AppLog write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func mirrorToOSLog(_ level: Level, category: String, message: String) {
        let logger = Logger(subsystem: subsystem, category: category)
        switch level {
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .warn:
            logger.warning("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        }
    }

    private static func logsDirectory() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = docs.appendingPathComponent("Logs", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func logFileName(for day: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return String(format: "knowell-%04d-%02d-%02d.log", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func pruneOldLogs(in folder: URL, keepingDays: Int) throws {
        let fm = FileManager.default
        let cutoff = Calendar.current.date(byAdding: .day, value: -keepingDays, to: .now) ?? .distantPast
        let files = try fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        for url in files where url.pathExtension == "log" {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values.contentModificationDate, modified < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }
}
