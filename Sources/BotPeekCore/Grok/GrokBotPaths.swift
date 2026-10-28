import Foundation

/// Facts about the Grok Bot desktop app that BotPeek depends on.
///
/// None of these are a documented public interface. They were verified by
/// community projects (see docs/INTEGRATION.md) and are kept in one place so
/// that a Grok Bot update only needs changes here.
public enum GrokBotApp {
    public static let bundleIdentifier = "com.anysphere.sand"
    public static let displayName = "Grok Bot"
    public static let downloadURL = URL(string: "https://cursor.com/grok-bot")!
}

/// Locations of Grok Bot's local data. BotPeek only ever reads these.
public struct GrokBotPaths: Equatable, Sendable {
    public let supportDirectory: URL

    public init(supportDirectory: URL) {
        self.supportDirectory = supportDirectory
    }

    public static func standard(homeDirectory: URL) -> GrokBotPaths {
        GrokBotPaths(
            supportDirectory: homeDirectory
                .appendingPathComponent("Library/Application Support/Grok Bot", isDirectory: true)
        )
    }

    /// Key-value cache where the bot roster lives, one `.blob` file per key.
    public var persistenceDirectory: URL {
        supportDirectory.appendingPathComponent("sand-client-persistence", isDirectory: true)
    }

    /// Uploaded profile images, one file per 32-hex-character key.
    public var avatarsDirectory: URL {
        supportDirectory.appendingPathComponent("roster-avatars", isDirectory: true)
    }

    /// Written by the running app: `{ "pid": …, "signedIn": …, "appVersion": … }`.
    public var desktopStatusFile: URL {
        supportDirectory.appendingPathComponent("desktop-status.json")
    }
}

/// RFC 4648 base32 without padding, as used for persistence file names.
public enum Base32 {
    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
    private static let lookup: [Character: Int] = {
        var table: [Character: Int] = [:]
        for (index, character) in alphabet.enumerated() { table[character] = index }
        return table
    }()

    public static func decode(_ input: String) -> Data? {
        var buffer = 0
        var bits = 0
        var output = Data()
        for character in input.lowercased() where character != "=" {
            guard let value = lookup[character] else { return nil }
            buffer = (buffer << 5) | value
            bits += 5
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((buffer >> bits) & 0xff))
                buffer &= (1 << bits) - 1
            }
        }
        return output
    }

    public static func encode(_ data: Data) -> String {
        var output = ""
        var buffer = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                output.append(alphabet[(buffer >> bits) & 31])
            }
            buffer &= (1 << bits) - 1
        }
        if bits > 0 { output.append(alphabet[(buffer << (5 - bits)) & 31]) }
        return output
    }

    /// Decodes a persistence file name (without `.blob`) to its cache key.
    public static func decodeKey(fileName: String) -> String? {
        guard let data = decode(fileName) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
