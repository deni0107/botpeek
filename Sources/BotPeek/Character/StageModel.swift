#if canImport(AppKit)
import SwiftUI
import BotPeekCore

/// Actions the speech bubble can trigger. Implemented by `CharacterWindowManager`.
@MainActor
protocol StageActions: AnyObject {
    func expand()
    func collapse()
    func send(_ reply: Reply)
    func snooze()
    func dismiss()
    func openInGrokBot()
    func showNext()
    func showPrevious()
    /// Switches to a waiting bot from the stack.
    func focus(_ id: RequestID)
    /// The character is being dragged along the edge.
    func dragChanged()
    func dragEnded()
    func loadQuestion()
    func requestAccessibility()
}

struct QueuePosition: Equatable {
    var index: Int
    var count: Int
}

/// Another bot waiting its turn, shown tucked against the edge.
struct WaitingBot: Identifiable, Equatable {
    var id: RequestID
    var name: String
    var avatar: AvatarSource
    var waitingSince: Date
}

/// Everything the on-screen character and bubble display.
@MainActor
final class StageModel: ObservableObject {
    @Published var request: AttentionRequest?
    @Published var avatar: AvatarSource = .builtIn(shape: .classic, color: .defaultColor)
    @Published var machine = CharacterStateMachine()
    @Published var pose = MotionPose(hidden: 1, curve: .easeOut(duration: 0))
    @Published var bubbleVisible = false
    @Published var isExpanded = false
    @Published var delivery: DeliveryState = .idle
    @Published var queue: QueuePosition?
    @Published var edge: ScreenEdge = .right
    /// Upper half of a side edge: the bubble and stack hang below the character.
    @Published var growsDown = false
    @Published var characterSize: CGFloat = 72
    @Published var isDemo = false
    @Published var canApproveInline = false
    @Published var replyUnavailableReason: String?
    @Published var isLoadingContent = false
    @Published var contentError: String?
    @Published var snoozeMinutes = 15
    @Published var reduceMotion = false
    @Published var isHovering = false
    @Published var isHoveringBubble = false
    /// Other waiting bots, next in line first, and how many more don't fit.
    @Published var waiting: [WaitingBot] = []
    @Published var waitingOverflow = 0
    /// The bubble tucked itself away after a while without interaction.
    @Published var isShrunk = false
    /// Shown in the collapsed bubble when the global shortcut works.
    @Published var shortcutHint: String?

    weak var actions: StageActions?

    var phase: CharacterPhase { machine.phase }

    var botName: String { request?.bot.name ?? "" }
}
#endif
