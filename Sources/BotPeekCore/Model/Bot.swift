import Foundation

/// Grok Bot's own identifier for a bot. BotPeek never invents these.
public struct BotID: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static func < (lhs: BotID, rhs: BotID) -> Bool { lhs.rawValue < rhs.rawValue }

    /// A short, non-reversible tag for logs, so diagnostics never contain bot names.
    public var logTag: String { "bot#" + StableHash.fnv1a(rawValue).prefix(6) }

    public var description: String { rawValue }
}

/// Who a bot is: everything BotPeek needs to draw it and route replies to it.
public struct BotIdentity: Equatable, Hashable, Codable, Sendable, Identifiable {
    public let id: BotID
    public var name: String
    public var avatar: AvatarDescriptor

    public init(id: BotID, name: String, avatar: AvatarDescriptor) {
        self.id = id
        self.name = name
        self.avatar = avatar
    }
}

/// One row of Grok Bot's local roster.
public struct Bot: Equatable, Sendable, Identifiable {
    public var identity: BotIdentity
    public var description: String?
    /// The raw "awaiting user response" payload. Non-empty means the bot is
    /// blocked on the user. Kept only in memory and never written to disk.
    public var awaitingUserResponse: JSONValue?
    public var hasUnread: Bool
    public var unreadCount: Int
    public var lastActivity: Date?
    public var isHiddenFromSidebar: Bool

    public var id: BotID { identity.id }
    public var name: String { identity.name }

    public init(
        identity: BotIdentity,
        description: String? = nil,
        awaitingUserResponse: JSONValue? = nil,
        hasUnread: Bool = false,
        unreadCount: Int = 0,
        lastActivity: Date? = nil,
        isHiddenFromSidebar: Bool = false
    ) {
        self.identity = identity
        self.description = description
        self.awaitingUserResponse = awaitingUserResponse
        self.hasUnread = hasUnread
        self.unreadCount = unreadCount
        self.lastActivity = lastActivity
        self.isHiddenFromSidebar = isHiddenFromSidebar
    }
}
