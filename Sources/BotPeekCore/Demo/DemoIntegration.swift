import Foundation

/// Sample bots for trying BotPeek without Grok Bot.
///
/// Everything here is clearly labelled as a demo in the UI. The demo bots use
/// BotPeek's built-in shapes; they are not stand-ins for the user's real bots.
public final class DemoIntegration: GrokIntegration, ReplyService {
    public struct ScriptedBot: Sendable {
        public var bot: Bot
        /// Seconds after the demo starts when the bot asks for attention.
        /// `nil` = never (shows that ordinary activity does not pop up).
        public var asksAfter: Double?
        public var content: AttentionContent
    }

    public let isDemo = true
    public var replyService: ReplyService { self }
    public let capabilities = ReplyCapabilities(text: true, choices: true, approvals: true)

    /// Replies containing this text fail, to demonstrate error handling.
    public static let failureKeyword = "#fail"

    public private(set) var script: [ScriptedBot]
    private var startedAt: Date
    private var answeredAt: [BotID: Date] = [:]
    private let lock = NSLock()
    private let replyDelay: Double

    public init(startedAt: Date = Date(), replyDelay: Double = 1.1, script: [ScriptedBot] = DemoIntegration.defaultScript) {
        self.startedAt = startedAt
        self.replyDelay = replyDelay
        self.script = script
    }

    public func restart(at date: Date) {
        lock.lock()
        startedAt = date
        answeredAt.removeAll()
        lock.unlock()
    }

    // MARK: BotStatusMonitor

    public func currentSnapshot(now: Date) -> StatusSnapshot {
        lock.lock()
        defer { lock.unlock() }
        var bots: [Bot] = []
        var observations: [AttentionObservation] = []
        for item in script {
            bots.append(item.bot)
            guard let after = item.asksAfter,
                  now.timeIntervalSince(startedAt) >= after,
                  answeredAt[item.bot.id].map({ now < $0 }) ?? true
            else { continue }
            let fingerprint = "d:" + StableHash.fnv1a(item.bot.id.rawValue + (item.content.prompt ?? ""))
            observations.append(AttentionObservation(bot: item.bot.identity, fingerprint: fingerprint, content: item.content, source: .demo))
        }
        return StatusSnapshot(observedAt: now, bots: bots.map(\.identity), attention: observations)
    }

    // MARK: AvatarProvider

    public func avatarSource(for bot: BotIdentity) -> AvatarSource {
        .builtIn(shape: bot.avatar.shape, color: bot.avatar.color)
    }

    // MARK: ConversationProvider

    public func loadContent(for request: AttentionRequest, allowNavigation: Bool) async throws -> AttentionContent? { nil }

    public func openInGrokBot(bot: BotIdentity?) async {}

    // MARK: ReplyService

    public func deliver(_ reply: Reply, to target: ReplyTarget) async throws -> DeliveryReceipt {
        try await Task.sleep(nanoseconds: UInt64(replyDelay * 1_000_000_000))
        if case .text(let text) = reply, text.contains(Self.failureKeyword) {
            throw ReplyError.other("Demo: simulated delivery failure. Remove “\(Self.failureKeyword)” to send.")
        }
        let now = Date()
        // The demo bot "notices" the answer shortly after delivery.
        markAnswered(target.bot.id, clearsAt: now.addingTimeInterval(0.4))
        return DeliveryReceipt(verified: true, completedAt: now, method: "demo")
    }

    private func markAnswered(_ botID: BotID, clearsAt date: Date) {
        lock.lock()
        answeredAt[botID] = date
        lock.unlock()
    }

    public func health(now: Date) -> IntegrationHealth {
        IntegrationHealth(
            isDemo: true,
            grokBotInstalled: false,
            grokBotRunning: false,
            signedIn: nil,
            roster: .notApplicable,
            accessibility: .notApplicable
        )
    }

    // MARK: Script

    static func demoBot(_ id: String, _ name: String, shape: String, color: String, unread: Int = 0) -> Bot {
        Bot(
            identity: BotIdentity(id: BotID("demo-" + id), name: name, avatar: AvatarDescriptor(rawShape: shape, rawColor: color)),
            hasUnread: unread > 0,
            unreadCount: unread
        )
    }

    public static let defaultScript: [ScriptedBot] = [
        ScriptedBot(
            bot: demoBot("research", "Research Bot", shape: "cloud", color: "blue"),
            asksAfter: 2,
            content: AttentionContent(
                kind: .choice,
                prompt: "Hey! I found three potential vendors. Which should I contact?",
                choices: [
                    AttentionChoice(label: "Northwind Supply"),
                    AttentionChoice(label: "Acme Components"),
                    AttentionChoice(label: "Globex Parts"),
                ],
                source: .demo
            )
        ),
        ScriptedBot(
            bot: demoBot("travel", "Travel Planner", shape: "sparkle", color: "purple"),
            asksAfter: 9,
            content: AttentionContent(
                kind: .question,
                prompt: "Two hotels near the Lisbon venue fit your dates. Any preference on neighbourhood or budget before I book?",
                source: .demo
            )
        ),
        ScriptedBot(
            bot: demoBot("ops", "Ops Bot", shape: "square", color: "green"),
            asksAfter: 16,
            content: AttentionContent(
                kind: .approval,
                prompt: "I'd like to run the pending database migration on the staging server. It adds two columns and takes about a minute.",
                choices: [AttentionChoice(label: "Approve"), AttentionChoice(label: "Deny")],
                source: .demo
            )
        ),
        // Busy and finished bots: unread updates must never pop up.
        ScriptedBot(bot: demoBot("writer", "Writer", shape: "heart", color: "pink", unread: 2), asksAfter: nil, content: .opaque),
        ScriptedBot(bot: demoBot("inbox", "Inbox Bot", shape: "teardrop", color: "orange", unread: 5), asksAfter: nil, content: .opaque),
    ]
}
