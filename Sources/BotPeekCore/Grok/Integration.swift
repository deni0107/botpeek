import Foundation

// Interfaces between BotPeek and a source of bots. The live Grok Bot
// integration and the demo integration both implement them, and a future
// official API could replace the local-file + Accessibility approach without
// touching the UI.

/// Finds the user's existing bots and their identities.
public protocol BotDiscoveryService: AnyObject {
    func discoverBots() throws -> [Bot]
}

/// Produces snapshots of which bots need the user.
public protocol BotStatusMonitor: AnyObject {
    func currentSnapshot(now: Date) -> StatusSnapshot
}

/// Resolves how to draw a bot's avatar.
public protocol AvatarProvider: AnyObject {
    func avatarSource(for bot: BotIdentity) -> AvatarSource
}

/// Loads the full text of a request, for example from the conversation.
public protocol ConversationProvider: AnyObject {
    /// Returns better content for `request` if it can be read, otherwise `nil`.
    /// With `allowNavigation` false, only reads a conversation that is already
    /// open, so Grok Bot is never switched to another chat behind the user's back.
    func loadContent(for request: AttentionRequest, allowNavigation: Bool) async throws -> AttentionContent?
    /// Brings Grok Bot forward with the bot's conversation open, as a fallback.
    func openInGrokBot(bot: BotIdentity?) async
}

/// A complete integration: everything BotPeek needs from a source of bots.
public protocol GrokIntegration: BotStatusMonitor, AvatarProvider, ConversationProvider {
    var isDemo: Bool { get }
    var replyService: ReplyService { get }
    func health(now: Date) -> IntegrationHealth
}

// MARK: - Avatars

public enum AvatarSource: Equatable, Sendable {
    /// An uploaded profile image from Grok Bot's local avatar cache.
    case photo(URL)
    /// A built-in shape and color, drawn by BotPeek.
    case builtIn(shape: AvatarShape, color: AvatarColor)
    /// The bot has an uploaded image that BotPeek could not read. The built-in
    /// rendering is shown instead and the limitation is reported in Settings.
    case photoUnavailable(shape: AvatarShape, color: AvatarColor)
}

public enum AvatarResolver {
    public static let maximumPhotoSize = 20 * 1_024 * 1_024

    public static func resolve(_ avatar: AvatarDescriptor, paths: GrokBotPaths, fileManager: FileManager = .default) -> AvatarSource {
        let shape = avatar.shape
        let color = avatar.color
        guard let key = avatar.photoKey else { return .builtIn(shape: shape, color: color) }
        let url = paths.avatarsDirectory.appendingPathComponent(key, isDirectory: false)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= maximumPhotoSize
        else { return .photoUnavailable(shape: shape, color: color) }
        return .photo(url)
    }
}

// MARK: - Health

public enum PermissionState: String, Equatable, Sendable {
    case granted
    case denied
    case notApplicable
}

public enum RosterHealth: Equatable, Sendable {
    case ok(botCount: Int, knownSchema: Bool)
    case failed(RosterStoreError)
    case notApplicable
}

/// What BotPeek currently knows about its connection, for Settings and diagnostics.
public struct IntegrationHealth: Equatable, Sendable {
    public var isDemo: Bool
    public var grokBotInstalled: Bool
    public var grokBotVersion: String?
    public var grokBotRunning: Bool
    public var signedIn: Bool?
    public var roster: RosterHealth
    public var accessibility: PermissionState
    public var photoAvatarsUnavailable: Int
    public var unrecognizedAvatarShapes: [String]

    public init(
        isDemo: Bool,
        grokBotInstalled: Bool,
        grokBotVersion: String? = nil,
        grokBotRunning: Bool,
        signedIn: Bool?,
        roster: RosterHealth,
        accessibility: PermissionState,
        photoAvatarsUnavailable: Int = 0,
        unrecognizedAvatarShapes: [String] = []
    ) {
        self.isDemo = isDemo
        self.grokBotInstalled = grokBotInstalled
        self.grokBotVersion = grokBotVersion
        self.grokBotRunning = grokBotRunning
        self.signedIn = signedIn
        self.roster = roster
        self.accessibility = accessibility
        self.photoAvatarsUnavailable = photoAvatarsUnavailable
        self.unrecognizedAvatarShapes = unrecognizedAvatarShapes
    }

    /// One-line status for the menu bar and Settings.
    public var summary: String {
        if isDemo { return "Demo mode: showing sample bots, not your Grok Bot." }
        if !grokBotInstalled { return "Grok Bot isn't installed." }
        if case .failed(let error) = roster { return error.userMessage }
        if signedIn == false { return "Grok Bot is signed out." }
        if case .ok(let count, let known) = roster {
            var text = "Watching \(count) bot\(count == 1 ? "" : "s")"
            if !grokBotRunning { text += " (Grok Bot is closed)" }
            if !known { text += ". Grok Bot's data format changed; some details may be missing" }
            return text + "."
        }
        return "Not connected."
    }

    /// Whether inline replies can work right now.
    public var canReply: Bool {
        isDemo || (grokBotRunning && accessibility == .granted)
    }
}
