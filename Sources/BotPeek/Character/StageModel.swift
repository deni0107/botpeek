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
    func loadQuestion()
    func requestAccessibility()
}

struct QueuePosition: Equatable {
    var index: Int
    var count: Int
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
    @Published var characterSize: CGFloat = 72
    @Published var isDemo = false
    @Published var canApproveInline = false
    @Published var replyUnavailableReason: String?
    @Published var isLoadingContent = false
    @Published var contentError: String?
    @Published var snoozeMinutes = 15
    @Published var reduceMotion = false
    @Published var isHovering = false

    weak var actions: StageActions?

    var phase: CharacterPhase { machine.phase }

    var botName: String { request?.bot.name ?? "" }
}
#endif
