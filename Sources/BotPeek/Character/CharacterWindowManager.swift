#if canImport(AppKit)
import AppKit
import Combine
import SwiftUI
import BotPeekCore

extension MotionCurve {
    var animation: Animation {
        switch self {
        case .spring(let spec): return .spring(response: spec.response, dampingFraction: spec.dampingFraction)
        case .easeOut(let duration): return .easeOut(duration: duration)
        case .easeIn(let duration): return .easeIn(duration: duration)
        }
    }

    var duration: Double {
        switch self {
        case .spring(let spec): return spec.response
        case .easeOut(let duration), .easeIn(let duration): return duration
        }
    }
}

/// Runs `AnimationPlan` sequences on the stage, one at a time.
@MainActor
final class AnimationCoordinator {
    private var task: Task<Void, Never>?

    func cancel() {
        task?.cancel()
        task = nil
    }

    func run(_ steps: [MotionPose], on stage: StageModel, completion: @escaping @MainActor () -> Void) {
        cancel()
        task = Task { @MainActor in
            for step in steps {
                if step.delay > 0 { try? await Task.sleep(nanoseconds: UInt64(step.delay * 1_000_000_000)) }
                if Task.isCancelled { return }
                withAnimation(step.curve.animation) { stage.pose = step }
            }
            if let last = steps.last { try? await Task.sleep(nanoseconds: UInt64(last.curve.duration * 1_000_000_000)) }
            if Task.isCancelled { return }
            completion()
        }
    }

    static func set(_ pose: MotionPose, on stage: StageModel) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { stage.pose = pose }
    }
}

/// Shows one request at a time as a character peeking from the screen edge.
@MainActor
final class CharacterWindowManager: StageActions {
    private let app: AppModel
    private let stage = StageModel()
    private let panel = CharacterPanel()
    private let animator = AnimationCoordinator()
    private lazy var tracker = ClickThroughTracker(panel: panel)
    private var cancellables = Set<AnyCancellable>()
    private var plan = AnimationPlan.make(intensity: .lively, reduceMotion: false)
    private var bubbleTask: Task<Void, Never>?
    private var lastShowToken = 0
    /// The app that was frontmost before the user started typing in the bubble.
    private var previousApp: NSRunningApplication?

    init(app: AppModel) {
        self.app = app
        stage.actions = self
        let host = NSHostingView(rootView: CharacterStageView(model: stage) { [weak self] rects in
            self?.tracker.interactiveRects = rects
        })
        host.sizingOptions = []
        panel.contentView = host

        app.$settings
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.settingsChanged() }
            }
            .store(in: &cancellables)
        app.$deliveryStates
            .sink { [weak self] _ in
                Task { @MainActor in self?.deliveryChanged() }
            }
            .store(in: &cancellables)
        app.$health
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshCapabilities() }
            }
            .store(in: &cancellables)
        app.$showRequestToken
            .sink { [weak self] token in
                Task { @MainActor in self?.showRequested(token: token) }
            }
            .store(in: &cancellables)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.positionPanel() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.settingsChanged() }
        }
        settingsChanged()
    }

    var isShowing: Bool { stage.machine.isVisible }

    // MARK: Sync with the queue

    /// Decides what should be on screen. Called after every model change.
    func sync() {
        guard app.settings.isEnabled else {
            if stage.machine.isVisible { leave() }
            return
        }
        switch stage.phase {
        case .sending, .celebrating:
            // Let the reply finish; then the next request gets its turn.
            if let current = stage.request, let updated = app.request(current.id) { stage.request = updated }
            return
        default:
            break
        }

        let presentable = app.presentable
        guard let target = RequestQueue.current(in: presentable, preferred: app.focusedRequestID) else {
            if stage.machine.isVisible, stage.phase != .exiting { leave() }
            return
        }
        stage.queue = RequestQueue.position(of: target.id, in: presentable).map { QueuePosition(index: $0.index, count: $0.count) }

        switch stage.phase {
        case .hidden, .exiting:
            enter(with: target)
        default:
            guard let current = stage.request else { return enter(with: target) }
            if current.id == target.id {
                stage.request = target
                refreshCapabilities()
            } else if current.botID == target.botID || app.focusedRequestID == target.id {
                // Same bot asking something new, or the user switched requests.
                swap(to: target)
            } else {
                // A different bot's turn: this one leaves, the next one enters.
                leave()
            }
        }
    }

    private func showRequested(token: Int) {
        guard token != lastShowToken else { return }
        lastShowToken = token
        if let target = app.currentRequest, stage.request?.id != target.id, stage.machine.isVisible {
            swap(to: target)
        }
        sync()
    }

    // MARK: Transitions

    private func enter(with request: AttentionRequest) {
        animator.cancel()
        bubbleTask?.cancel()
        load(request)
        stage.isExpanded = false
        stage.bubbleVisible = false
        stage.machine.handle(.present)
        AnimationCoordinator.set(plan.initial, on: stage)

        positionPanel()
        panel.orderFrontRegardless()
        tracker.start()

        if app.settings.soundsEnabled { NSSound(named: NSSound.Name("Pop"))?.play() }
        announce("\(request.bot.name) needs your attention: \(request.content.displayPrompt)")
        app.log.record(.debug, "ui", "Character entering for \(request.id)")

        let bubbleDelay = plan.bubbleDelay
        bubbleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(bubbleDelay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            withAnimation(self.bubbleAnimation) { self.stage.bubbleVisible = true }
        }
        animator.run(plan.entrance, on: stage) { [weak self] in
            self?.stage.machine.handle(.animationFinished)
        }
    }

    private func swap(to request: AttentionRequest) {
        withAnimation(stage.reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            load(request)
            stage.isExpanded = false
        }
        if stage.phase == .expanded { stage.machine.handle(.collapse) }
    }

    private func leave(then next: (() -> Void)? = nil) {
        bubbleTask?.cancel()
        guard stage.machine.handle(.leave) || stage.phase == .exiting else {
            next?()
            return
        }
        returnFocus()
        withAnimation(bubbleAnimation) { stage.bubbleVisible = false }
        animator.run(plan.exit, on: stage) { [weak self] in
            self?.finishExit()
        }
    }

    private func finishExit() {
        stage.machine.handle(.animationFinished)
        guard stage.phase == .hidden else { return }
        panel.orderOut(nil)
        tracker.stop()
        stage.request = nil
        stage.isExpanded = false
        stage.delivery = .idle
        // Whoever is next in the queue may now enter.
        sync()
    }

    private func celebrate() {
        guard stage.machine.handle(.sendSucceeded) else { return }
        returnFocus()
        let steps = plan.celebration
        animator.run(steps, on: stage) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                // Let "Delivered" register before leaving.
                try? await Task.sleep(nanoseconds: steps.isEmpty ? 900_000_000 : 350_000_000)
                self.stage.machine.handle(.animationFinished)
                self.stage.machine.handle(.leave)
                withAnimation(self.bubbleAnimation) { self.stage.bubbleVisible = false }
                if let id = self.stage.request?.id { self.app.clearDeliveryState(id) }
                self.animator.run(self.plan.exit, on: self.stage) { [weak self] in self?.finishExit() }
            }
        }
    }

    private var bubbleAnimation: Animation? {
        stage.reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.78)
    }

    private func load(_ request: AttentionRequest) {
        stage.request = request
        stage.avatar = app.avatarSource(for: request.bot)
        stage.delivery = app.deliveryState(for: request.id)
        refreshCapabilities()
    }

    // MARK: Settings and capabilities

    private func settingsChanged() {
        let settings = app.settings
        let reduceMotion = settings.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        plan = AnimationPlan.make(intensity: settings.animationIntensity, reduceMotion: reduceMotion)
        stage.reduceMotion = reduceMotion
        stage.edge = settings.edge
        stage.characterSize = CGFloat(settings.characterSize.points)
        stage.snoozeMinutes = settings.snoozeMinutes
        stage.isDemo = settings.demoMode
        if stage.machine.isVisible { positionPanel() }
        refreshCapabilities()
        sync()
    }

    private func refreshCapabilities() {
        guard let request = stage.request else { return }
        let health = app.health
        stage.isDemo = health.isDemo
        stage.canApproveInline = app.canApproveInline(request)
        stage.isLoadingContent = app.loadingContent.contains(request.id)
        stage.contentError = app.contentErrors[request.id]
        if health.isDemo {
            stage.replyUnavailableReason = nil
        } else if !health.grokBotRunning {
            stage.replyUnavailableReason = "Grok Bot isn't running, so BotPeek can't reply for you."
        } else if health.accessibility != .granted {
            stage.replyUnavailableReason = "BotPeek needs Accessibility permission to reply for you."
        } else {
            stage.replyUnavailableReason = nil
        }
    }

    private func deliveryChanged() {
        guard let id = stage.request?.id else { return }
        let state = app.deliveryState(for: id)
        stage.delivery = state
        switch state {
        case .sending:
            stage.machine.handle(.beginSend)
        case .delivered:
            celebrate()
        case .failed:
            if stage.phase == .sending { stage.machine.handle(.sendFailed) }
            stage.isExpanded = true
        case .idle:
            break
        }
    }

    // MARK: Placement

    private func positionPanel() {
        let settings = app.settings
        let screen: NSScreen?
        switch settings.screen {
        case .followMouse:
            let mouse = NSEvent.mouseLocation
            screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        case .primary:
            screen = NSScreen.screens.first
        }
        guard let visible = screen?.visibleFrame else { return }
        let size = PanelPlacement.contentSize(
            characterSize: settings.characterSize.points,
            bubbleSize: CGSize(width: SpeechBubble.width, height: 400),
            edge: settings.edge
        )
        let frame = PanelPlacement.frame(contentSize: size, edge: settings.edge, position: settings.edgePosition, visibleFrame: visible)
        panel.setFrame(frame, display: true)
        tracker.update()
    }

    // MARK: StageActions

    func expand() {
        guard stage.request != nil else { return }
        if stage.phase == .entering || stage.phase == .presented { stage.machine.handle(.expand) }
        if !stage.bubbleVisible { withAnimation(bubbleAnimation) { stage.bubbleVisible = true } }
        stage.isExpanded = true
        if previousApp == nil { previousApp = NSWorkspace.shared.frontmostApplication }
        // Becoming key lets the text field receive typing without activating BotPeek.
        panel.makeKey()
        if let request = stage.request, !request.content.hasReadableContent, !app.health.isDemo {
            Task { await app.loadContent(for: request.id, allowNavigation: false) }
        }
    }

    func collapse() {
        stage.isExpanded = false
        if stage.phase == .expanded { stage.machine.handle(.collapse) }
        returnFocus()
    }

    func send(_ reply: Reply) {
        guard let id = stage.request?.id else { return }
        if let error = app.validate(reply, for: id) {
            stage.delivery = .failed(error)
            return
        }
        Task { await app.send(reply, for: id) }
    }

    func snooze() {
        guard let id = stage.request?.id else { return }
        app.snooze(id)
    }

    func dismiss() {
        guard let id = stage.request?.id else { return }
        app.dismiss(id)
    }

    func openInGrokBot() {
        app.openInGrokBot(stage.request)
    }

    func showNext() {
        app.showNext()
    }

    func showPrevious() {
        app.showPrevious()
    }

    func loadQuestion() {
        guard let id = stage.request?.id else { return }
        Task {
            await app.loadContent(for: id, allowNavigation: true)
            refreshCapabilities()
        }
    }

    func requestAccessibility() {
        app.requestAccessibility()
    }

    // MARK: Focus and accessibility

    /// Gives keyboard focus back to the app the user was using.
    private func returnFocus() {
        guard panel.isKeyWindow else {
            previousApp = nil
            return
        }
        let target = previousApp
        previousApp = nil
        if let target, !target.isTerminated, target.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            _ = target.activate(options: [])
        }
    }

    private func announce(_ text: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}
#endif
