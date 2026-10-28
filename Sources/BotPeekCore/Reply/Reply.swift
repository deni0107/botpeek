import Foundation

public enum ApprovalDecision: String, Equatable, Sendable {
    case approve
    case deny
}

/// A response the user composed in BotPeek.
public enum Reply: Equatable, Sendable {
    case text(String)
    case choice(AttentionChoice)
    /// An approve/deny decision. `option` is the exact button that will be
    /// pressed, shown to the user before they confirm.
    case approval(ApprovalDecision, option: AttentionChoice)

    /// A non-identifying description for logs.
    public var logDescription: String {
        switch self {
        case .text(let text): return "text(\(text.count) chars)"
        case .choice: return "choice"
        case .approval(let decision, _): return "approval(\(decision.rawValue))"
        }
    }
}

/// The exact existing bot and request a reply must reach.
public struct ReplyTarget: Equatable, Sendable {
    public var requestID: RequestID
    public var bot: BotIdentity
    public var content: AttentionContent

    public init(requestID: RequestID, bot: BotIdentity, content: AttentionContent) {
        self.requestID = requestID
        self.bot = bot
        self.content = content
    }
}

public struct DeliveryReceipt: Equatable, Sendable {
    /// True only when BotPeek saw the reply land in the conversation.
    public var verified: Bool
    public var completedAt: Date
    public var method: String

    public init(verified: Bool, completedAt: Date, method: String) {
        self.verified = verified
        self.completedAt = completedAt
        self.method = method
    }
}

public enum ReplyError: Error, Equatable, Sendable {
    case emptyMessage
    case messageTooLong(limit: Int)
    case requestNoLongerActive
    case alreadySending
    case choiceNotOffered
    case approvalRequiresGrokBot
    case unsupported
    case accessibilityPermissionMissing
    case grokBotNotRunning
    case grokBotWindowUnavailable
    case botNotFound
    case ambiguousBot
    case conversationMismatch
    case composerNotFound
    case questionNotFound
    /// An action reached Grok Bot but BotPeek could not see the result.
    /// Never retried automatically, to avoid sending twice.
    case deliveryUnconfirmed
    case timedOut
    case other(String)

    public var userMessage: String {
        switch self {
        case .emptyMessage: return "Type a reply first."
        case .messageTooLong(let limit): return "That reply is too long (limit \(limit) characters)."
        case .requestNoLongerActive: return "This request was already answered or withdrawn."
        case .alreadySending: return "A reply to this request is already being sent."
        case .choiceNotOffered: return "That option is no longer offered. Open Grok Bot to answer."
        case .approvalRequiresGrokBot: return "Approvals are handled in Grok Bot so you can review them there."
        case .unsupported: return "This kind of reply can't be sent from BotPeek yet."
        case .accessibilityPermissionMissing: return "BotPeek needs Accessibility permission to reply for you."
        case .grokBotNotRunning: return "Grok Bot isn't running. Open it and try again."
        case .grokBotWindowUnavailable: return "Grok Bot's window isn't available. Open its main window and try again."
        case .botNotFound: return "Couldn't find this bot in Grok Bot's sidebar."
        case .ambiguousBot: return "More than one bot has this name, so BotPeek won't guess. Answer in Grok Bot."
        case .conversationMismatch: return "Grok Bot opened a different conversation, so nothing was sent."
        case .composerNotFound: return "Couldn't find Grok Bot's message box."
        case .questionNotFound: return "Couldn't find the question in the conversation."
        case .deliveryUnconfirmed: return "BotPeek couldn't confirm delivery. Check Grok Bot before trying again."
        case .timedOut: return "Grok Bot took too long to respond."
        case .other(let message): return message
        }
    }

    /// Whether retrying from BotPeek is safe (nothing reached Grok Bot).
    public var isSafeToRetry: Bool {
        switch self {
        case .deliveryUnconfirmed, .requestNoLongerActive, .alreadySending: return false
        default: return true
        }
    }
}

public struct ReplyCapabilities: Equatable, Sendable {
    public var text: Bool
    public var choices: Bool
    public var approvals: Bool

    public init(text: Bool, choices: Bool, approvals: Bool) {
        self.text = text
        self.choices = choices
        self.approvals = approvals
    }

    public static let none = ReplyCapabilities(text: false, choices: false, approvals: false)
}

/// Delivers replies to Grok Bot. Implementations must target the existing
/// conversation of `target.bot` and must never create bots or conversations.
public protocol ReplyService: AnyObject {
    var capabilities: ReplyCapabilities { get }
    func deliver(_ reply: Reply, to target: ReplyTarget) async throws -> DeliveryReceipt
}

public enum DeliveryState: Equatable, Sendable {
    case idle
    case sending
    /// Seen in the conversation. Only this state may be shown as "Sent".
    case delivered(DeliveryReceipt)
    case failed(ReplyError)
}
