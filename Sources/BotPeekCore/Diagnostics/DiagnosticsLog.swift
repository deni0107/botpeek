import Foundation

/// An in-memory, privacy-preserving event log for troubleshooting.
///
/// Callers must never pass message text, bot names or file contents; use
/// `BotID.logTag` and counts instead. The log is not written to disk unless the
/// user exports it from the menu.
public final class DiagnosticsLog: @unchecked Sendable {
    public enum Level: String, Sendable {
        case debug, info, warning, error
    }

    public struct Entry: Equatable, Sendable {
        public var date: Date
        public var level: Level
        public var category: String
        public var message: String
    }

    public let capacity: Int
    private var entries: [Entry] = []
    private let lock = NSLock()
    /// Mirrors entries to the system log (set by the macOS app).
    public var sink: ((Entry) -> Void)?

    public init(capacity: Int = 500) {
        self.capacity = capacity
    }

    public func record(_ level: Level, _ category: String, _ message: String, date: Date = Date()) {
        let entry = Entry(date: date, level: level, category: category, message: message)
        lock.lock()
        entries.append(entry)
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
        lock.unlock()
        sink?(entry)
    }

    public var allEntries: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    public func export(header: [String: String]) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["BotPeek diagnostics", "Contains no message contents or bot names.", ""]
        for key in header.keys.sorted() {
            lines.append("\(key): \(header[key] ?? "")")
        }
        lines.append("")
        for entry in allEntries {
            lines.append("\(formatter.string(from: entry.date)) [\(entry.level.rawValue)] \(entry.category): \(entry.message)")
        }
        return lines.joined(separator: "\n")
    }
}
