import Foundation

public enum RosterStoreError: Error, Equatable, Sendable {
    /// `~/Library/Application Support/Grok Bot` does not exist.
    case grokBotDataMissing
    /// The folder exists but holds no roster yet (for example: signed out).
    case rosterNotFound
    case unreadable
    case tooLarge
    case parse(RosterParseError)

    public var userMessage: String {
        switch self {
        case .grokBotDataMissing: return "Grok Bot doesn't seem to be installed or hasn't been opened yet."
        case .rosterNotFound: return "Grok Bot has no saved bot list yet. Open Grok Bot and sign in."
        case .unreadable: return "BotPeek couldn't read Grok Bot's bot list."
        case .tooLarge: return "Grok Bot's bot list is unexpectedly large, so BotPeek skipped it."
        case .parse: return "Grok Bot's bot list has a format BotPeek doesn't understand. Grok Bot may have been updated."
        }
    }
}

public struct RosterSnapshot: Equatable, Sendable {
    public var bots: [Bot]
    public var fileURL: URL
    public var modifiedAt: Date?
    public var schemaVersion: Int?
    public var isKnownSchema: Bool
    public var skippedRows: Int
}

/// Read-only access to Grok Bot's cached roster.
///
/// The roster file is located by decoding persistence file names (base32 of the
/// cache key) and picking the newest `*.roster.last-roster` entry, which belongs
/// to the account currently signed in. Results are cached by modification date
/// and size so polling is cheap.
public final class RosterStore: @unchecked Sendable {
    public static let maximumFileSize = 8 * 1_024 * 1_024
    static let rosterKeySuffix = ".roster.last-roster"

    public let paths: GrokBotPaths
    private let fileManager: FileManager
    private let lock = NSLock()
    private var cache: (url: URL, modified: Date?, size: Int, snapshot: RosterSnapshot)?

    public init(paths: GrokBotPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func locateRosterFile() throws -> (url: URL, modified: Date?, size: Int) {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: paths.supportDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw RosterStoreError.grokBotDataMissing }

        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: paths.persistenceDirectory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw RosterStoreError.rosterNotFound
        }

        var best: (url: URL, modified: Date?, size: Int)?
        for url in entries where url.pathExtension == "blob" {
            guard let key = Base32.decodeKey(fileName: url.deletingPathExtension().lastPathComponent),
                  key.hasSuffix(Self.rosterKeySuffix),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true
            else { continue }
            let modified = values.contentModificationDate
            if best == nil || (modified ?? .distantPast) > (best?.modified ?? .distantPast) {
                best = (url, modified, values.fileSize ?? 0)
            }
        }
        guard let best else { throw RosterStoreError.rosterNotFound }
        return best
    }

    public func load() throws -> RosterSnapshot {
        let located = try locateRosterFile()
        guard located.size <= Self.maximumFileSize else { throw RosterStoreError.tooLarge }

        lock.lock()
        if let cache, cache.url == located.url, cache.modified == located.modified, cache.size == located.size {
            lock.unlock()
            return cache.snapshot
        }
        lock.unlock()

        guard let data = try? Data(contentsOf: located.url, options: [.mappedIfSafe]) else {
            throw RosterStoreError.unreadable
        }
        let result: RosterParseResult
        do {
            result = try RosterParser.parse(data)
        } catch let error as RosterParseError {
            throw RosterStoreError.parse(error)
        }
        let snapshot = RosterSnapshot(
            bots: result.bots,
            fileURL: located.url,
            modifiedAt: located.modified,
            schemaVersion: result.schemaVersion,
            isKnownSchema: result.isKnownSchema,
            skippedRows: result.skippedRows
        )
        lock.lock()
        cache = (located.url, located.modified, located.size, snapshot)
        lock.unlock()
        return snapshot
    }
}

/// Grok Bot's own record of whether it is running and signed in.
public struct DesktopStatus: Equatable, Sendable {
    public var pid: Int32
    public var signedIn: Bool
    public var appVersion: String?
}

public struct DesktopStatusReader: Sendable {
    public let paths: GrokBotPaths
    private let isProcessAlive: @Sendable (Int32) -> Bool

    public init(paths: GrokBotPaths, isProcessAlive: @escaping @Sendable (Int32) -> Bool = ProcessProbe.isAlive) {
        self.paths = paths
        self.isProcessAlive = isProcessAlive
    }

    /// Returns the status only if the recorded process is still alive, so a
    /// stale file left behind by a crash is not mistaken for a running app.
    public func load() -> DesktopStatus? {
        guard let data = try? Data(contentsOf: paths.desktopStatusFile),
              let json = try? JSONValue.parse(data),
              let pidNumber = json["pid"]?.numberValue,
              pidNumber > 0, pidNumber < Double(Int32.max)
        else { return nil }
        let pid = Int32(pidNumber)
        guard isProcessAlive(pid) else { return nil }
        return DesktopStatus(
            pid: pid,
            signedIn: json["signedIn"]?.boolValue ?? false,
            appVersion: json["appVersion"]?.stringValue
        )
    }
}

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum ProcessProbe {
    @Sendable public static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
