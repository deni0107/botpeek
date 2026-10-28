import Foundation

public enum RosterParseError: Error, Equatable, Sendable {
    case notJSON
    case missingRows
}

public struct RosterParseResult: Equatable, Sendable {
    public var bots: [Bot]
    public var schemaVersion: Int?
    /// Rows that could not be understood (no id or name).
    public var skippedRows: Int

    /// `false` when the cache uses a schema version BotPeek has not been tested with.
    public var isKnownSchema: Bool {
        schemaVersion.map(RosterParser.testedSchemaVersions.contains) ?? false
    }
}

/// Parses Grok Bot's cached roster (`<account>.roster.last-roster`).
///
/// Observed layout (schema 4):
/// ```json
/// { "schemaVersion": 4,
///   "value": { "rows": [ { "id": "…", "name": "Research Bot",
///       "avatarShape": "cloud", "avatarColor": "blue",
///       "avatarPhoto": { "kind": "file", "key": "<32 hex>" },
///       "awaitingUserResponse": { … } | null,
///       "hasUnread": false, "unreadCount": 0,
///       "lastActivityAt": 1730000000000, "isHiddenFromSidebar": false } ] } }
/// ```
/// Every field is read defensively: unknown fields are ignored, missing ones
/// get safe defaults, and rows without an id or name are skipped.
public enum RosterParser {
    public static let testedSchemaVersions: Set<Int> = [4]

    public static func parse(_ data: Data) throws -> RosterParseResult {
        let root: JSONValue
        do {
            root = try JSONValue.parse(data)
        } catch {
            throw RosterParseError.notJSON
        }
        guard let rows = (root["value"]?["rows"] ?? root["rows"])?.arrayValue else {
            throw RosterParseError.missingRows
        }
        var bots: [Bot] = []
        var skipped = 0
        for row in rows {
            if let bot = parseRow(row) { bots.append(bot) } else { skipped += 1 }
        }
        let version = root["schemaVersion"]?.numberValue.map { Int($0) }
        return RosterParseResult(bots: bots, schemaVersion: version, skippedRows: skipped)
    }

    static func parseRow(_ row: JSONValue) -> Bot? {
        guard let id = row["id"]?.identifierString,
              let rawName = row["name"]?.stringValue
        else { return nil }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        var photoKey: String?
        if let photo = row["avatarPhoto"], photo["kind"]?.stringValue == "file" {
            photoKey = photo["key"]?.stringValue
        }
        let avatar = AvatarDescriptor(
            rawShape: row["avatarShape"]?.stringValue,
            rawColor: row["avatarColor"]?.stringValue,
            photoKey: photoKey
        )

        let awaiting = row["awaitingUserResponse"].flatMap { $0.isEmptySignal ? nil : $0 }
        let activity = ["lastActivityAt", "localActivityAt", "updatedAt"]
            .compactMap { row[$0]?.numberValue }
            .max()
            .map(date(fromTimestamp:))

        return Bot(
            identity: BotIdentity(id: BotID(id), name: name, avatar: avatar),
            description: row["description"]?.stringValue,
            awaitingUserResponse: awaiting,
            hasUnread: row["hasUnread"]?.boolValue ?? false,
            unreadCount: row["unreadCount"]?.numberValue.map { max(0, Int($0)) } ?? 0,
            lastActivity: activity,
            isHiddenFromSidebar: row["isHiddenFromSidebar"]?.boolValue ?? false
        )
    }

    /// Accepts both seconds and milliseconds since 1970.
    static func date(fromTimestamp value: Double) -> Date {
        Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1_000 : value)
    }
}
