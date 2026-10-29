import Foundation

/// What kind of human input a bot is waiting for.
public enum AttentionKind: String, Codable, Sendable {
    /// An open question answered with free text.
    case question
    /// A question with selectable answers.
    case choice
    /// A request to approve or deny an action.
    case approval
    /// The bot is waiting for instructions or a human handoff.
    case handoff
    /// The bot is waiting, but BotPeek could not tell for what.
    case unknown
}

public struct AttentionChoice: Equatable, Hashable, Codable, Sendable {
    public var label: String
    public var detail: String?

    public init(label: String, detail: String? = nil) {
        self.label = label
        self.detail = detail
    }
}

/// Where the text of a request came from.
public enum ContentSource: String, Codable, Sendable {
    /// Grok Bot's local roster payload.
    case roster
    /// The conversation transcript, read through Accessibility.
    case transcript
    /// Grok Bot's cached copy of the conversation, read from disk.
    case conversation
    /// The demo integration.
    case demo
    /// Nothing readable; BotPeek only knows that the bot is waiting.
    case none
}

/// The human-facing description of a request.
public struct AttentionContent: Equatable, Hashable, Codable, Sendable {
    public var kind: AttentionKind
    public var prompt: String?
    public var choices: [AttentionChoice]
    public var source: ContentSource
    /// Set when this request must be answered in Grok Bot itself (for example a
    /// form that asks for a password); the bubble then offers only that.
    public var grokBotOnlyReason: String?

    public init(
        kind: AttentionKind,
        prompt: String? = nil,
        choices: [AttentionChoice] = [],
        source: ContentSource,
        grokBotOnlyReason: String? = nil
    ) {
        self.kind = kind
        self.prompt = prompt
        self.choices = choices
        self.source = source
        self.grokBotOnlyReason = grokBotOnlyReason
    }

    public static let opaque = AttentionContent(kind: .unknown, prompt: nil, choices: [], source: .none)

    /// True when there is enough content to show and answer inline.
    public var hasReadableContent: Bool {
        !(prompt ?? "").isEmpty || !choices.isEmpty
    }

    /// Short text for the speech bubble when the prompt is missing.
    public var fallbackPrompt: String {
        switch kind {
        case .approval: return "I need your approval to continue."
        case .choice: return "I need you to pick an option."
        case .question: return "I have a question for you."
        case .handoff: return "I'm waiting for your instructions."
        case .unknown: return "I need your input to continue."
        }
    }

    public var displayPrompt: String { prompt.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackPrompt }
}

/// Which signal reported that a bot needs attention.
public enum AttentionSource: String, Codable, Sendable {
    case roster
    /// Grok Bot's cached conversation shows an unanswered question, approval or form.
    case conversation
    case accessibility
    case demo

    /// Read from Grok Bot's own data, as opposed to inferred from its window.
    public var isFromGrokBotData: Bool { self == .roster || self == .conversation }
}

/// A single observation that a bot is blocked on the user.
public struct AttentionObservation: Equatable, Sendable {
    public var bot: BotIdentity
    public var fingerprint: String
    public var content: AttentionContent
    public var source: AttentionSource

    public init(bot: BotIdentity, fingerprint: String, content: AttentionContent, source: AttentionSource) {
        self.bot = bot
        self.fingerprint = fingerprint
        self.content = content
        self.source = source
    }
}

/// Everything the status monitor saw at one moment.
public struct StatusSnapshot: Equatable, Sendable {
    public var observedAt: Date
    /// All bots currently known, including those that need nothing.
    public var bots: [BotIdentity]
    /// Bots that are blocked on the user.
    public var attention: [AttentionObservation]
    /// `false` when the source could not be read completely (for example the
    /// roster file is missing or mid-write). Incomplete snapshots never resolve
    /// existing requests, so a transient read error can't hide a real question.
    public var isComplete: Bool

    public init(observedAt: Date, bots: [BotIdentity], attention: [AttentionObservation], isComplete: Bool = true) {
        self.observedAt = observedAt
        self.bots = bots
        self.attention = attention
        self.isComplete = isComplete
    }

    public static func incomplete(at date: Date) -> StatusSnapshot {
        StatusSnapshot(observedAt: date, bots: [], attention: [], isComplete: false)
    }
}

/// Identifies one specific request: a bot plus the question it is asking.
public struct RequestID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let botID: BotID
    public let fingerprint: String

    public init(botID: BotID, fingerprint: String) {
        self.botID = botID
        self.fingerprint = fingerprint
    }

    public var rawValue: String { botID.rawValue + "|" + fingerprint }
    public var description: String { botID.logTag + "/" + fingerprint.prefix(8) }
}
