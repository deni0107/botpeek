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
    private var idleTask: Task<Void, Never>?
    private var nudgeTask: Task<Void, Never>?
    private var hopTask: Task<Void, Never>?
    private var isHopping = false
    private var lastShowToken = 0
    /// The app that was frontmost before the user started typing in the bubble.
    private var previousApp: NSRunningApplication?
    /// Where the panel is: the display's full and visible frames.
    private var screenFrame: CGRect?
    private var visibleFrame: CGRect?
    /// Pointer and drag anchor when a drag along the edge began, and where it is now.
    private var dragStart: (mouse: CGPoint, anchor: CGFloat)?
    private var dragPosition: Double?
    private lazy var hotKey = GlobalHotKey { [weak self] in self?.hotKeyPressed() }

    init(app: AppModel) {
        self.app = app
        stage.actions = self
        let host = NSHostingView(rootView: CharacterStageView(model: stage) { [weak self] rects in
            self?.tracker.interactiveRects = rects
        })
        host.sizingOptions = []
        panel.contentView = host
        tracker.onPointerMoved = { [weak self] in self?.pointerMoved() }

        stage.$isExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.app.setComposing(expanded, request: self.stage.request?.id)
                }
            }
            .store(in: &cancellables)
        stage.$isHovering
            .combineLatest(stage.$isHoveringBubble)
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
            .sink { [weak self] character, bubble in
                Task { @MainActor in self?.hoverChanged(character: character, bubble: bubble) }
            }
            .store(in: &cancellables)

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
        guard app.charactersActive else {
            updateWaiting(from: [], excluding: [])
            if stage.machine.isVisible { leave() }
            return
        }
        let presentable = app.presentable
        switch stage.phase {
        case .sending, .celebrating:
            // Let the reply finish; then the next request gets its turn.
            if let current = stage.request, let updated = app.request(current.id) { stage.request = updated }
            updateWaiting(from: presentable, excluding: [stage.request?.id])
            return
        default:
            break
        }

        guard let target = RequestQueue.current(in: presentable, preferred: app.focusedRequestID) else {
            updateWaiting(from: [], excluding: [])
            if stage.machine.isVisible, stage.phase != .exiting { leave() }
            return
        }
        updateWaiting(from: presentable, excluding: [stage.request?.id, target.id])
        stage.queue = RequestQueue.position(of: target.id, in: presentable).map { QueuePosition(index: $0.index, count: $0.count) }

        switch stage.phase {
        case .hidden:
            enter(with: target)
        case .exiting:
            // Let the exit finish (it syncs again), unless the leaving request came back.
            if stage.request?.id == target.id { enter(with: target) }
        default:
            guard let current = stage.request else { return enter(with: target) }
            if current.id == target.id {
                stage.request = target
                refreshCapabilities()
            } else if current.botID == target.botID || app.focusedRequestID == target.id {
                // Same bot asking something new, or the user switched requests.
                // Switching keeps the reply open, so the keyboard flow continues.
                swap(to: target, keepExpanded: stage.isExpanded && current.botID != target.botID)
            } else {
                // A different bot's turn: this one leaves, the next one enters.
                leave()
            }
        }
    }

    /// The other waiting bots, tucked along the edge next to the character.
    private func updateWaiting(from presentable: [AttentionRequest], excluding ids: [RequestID?]) {
        let others = presentable.filter { !ids.contains($0.id) }
        let split = PanelPlacement.stack(others)
        let waiting = split.shown.map {
            WaitingBot(id: $0.id, name: $0.bot.name, avatar: app.avatarSource(for: $0.bot), waitingSince: $0.firstSeen)
        }
        guard waiting != stage.waiting || split.overflow != stage.waitingOverflow else { return }
        withAnimation(stage.reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.8)) {
            stage.waiting = waiting
            stage.waitingOverflow = split.overflow
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
        stage.isShrunk = false
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
            guard let self else { return }
            self.stage.machine.handle(.animationFinished)
            self.scheduleIdleCollapse()
            self.scheduleNudges()
        }
    }

    private func swap(to request: AttentionRequest, keepExpanded: Bool = false) {
        withAnimation(stage.reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            load(request)
            if !keepExpanded { stage.isExpanded = false }
        }
        if keepExpanded {
            expand()
            scheduleNudges()
            return
        }
        if stage.phase == .expanded { stage.machine.handle(.collapse) }
        unshrink()
        scheduleIdleCollapse()
        scheduleNudges()
    }

    private func leave(then next: (() -> Void)? = nil) {
        bubbleTask?.cancel()
        cancelReminders()
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
        stage.isShrunk = false
        stage.delivery = .idle
        // Whoever is next in the queue may now enter.
        sync()
    }

    private func celebrate() {
        guard stage.machine.handle(.sendSucceeded) else { return }
        cancelReminders()
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

    // MARK: Idle collapse and reminders

    /// After a while without interaction the bubble tucks away, leaving the
    /// character (and the stack) so it stops covering what the user is doing.
    private func scheduleIdleCollapse() {
        idleTask?.cancel()
        guard app.settings.collapsesWhenIdle else { return }
        idleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(BotPeekSettings.idleCollapseDelay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.collapseIfIdle()
        }
    }

    private func collapseIfIdle() {
        guard stage.phase == .presented, !stage.isExpanded, stage.bubbleVisible, stage.delivery == .idle,
              !stage.isHovering, !stage.isHoveringBubble, dragStart == nil
        else { return }
        withAnimation(bubbleAnimation) { stage.bubbleVisible = false }
        stage.isShrunk = true
    }

    private func unshrink() {
        guard stage.isShrunk else { return }
        stage.isShrunk = false
        withAnimation(bubbleAnimation) { stage.bubbleVisible = true }
    }

    private func hoverChanged(character: Bool, bubble: Bool) {
        if character || bubble {
            idleTask?.cancel()
            // Hovering a tucked-away character brings its bubble back.
            if character, stage.phase == .presented { unshrink() }
        } else if stage.phase == .presented, !stage.isExpanded {
            scheduleIdleCollapse()
        }
    }

    /// A small wiggle every few minutes while the request stays unanswered.
    private func scheduleNudges() {
        nudgeTask?.cancel()
        guard app.settings.nudgesWhenIgnored, !plan.nudge.isEmpty, let id = stage.request?.id else { return }
        nudgeTask = Task { @MainActor [weak self] in
            for _ in 0..<BotPeekSettings.maxNudges {
                try? await Task.sleep(nanoseconds: UInt64(BotPeekSettings.nudgeInterval * 1_000_000_000))
                guard let self, !Task.isCancelled, self.stage.request?.id == id else { return }
                guard self.stage.phase == .presented, !self.stage.isExpanded, !self.isHopping, self.dragStart == nil else { continue }
                self.animator.run(self.plan.nudge, on: self.stage) {}
            }
        }
    }

    private func cancelReminders() {
        idleTask?.cancel()
        nudgeTask?.cancel()
        hopTask?.cancel()
        hopTask = nil
    }

    // MARK: Settings and capabilities

    private func settingsChanged() {
        let settings = app.settings
        let reduceMotion = settings.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        plan = AnimationPlan.make(intensity: settings.animationIntensity, reduceMotion: reduceMotion)
        stage.reduceMotion = reduceMotion
        stage.edge = settings.edge
        if dragStart == nil { stage.growsDown = PanelPlacement.growsDown(edge: settings.edge, position: settings.edgePosition) }
        stage.characterSize = CGFloat(settings.characterSize.points)
        stage.snoozeMinutes = settings.snoozeMinutes
        stage.isDemo = settings.demoMode
        panel.sharingType = settings.hideFromScreenCapture ? .none : .readOnly
        if settings.globalShortcutEnabled { hotKey.register() } else { hotKey.unregister() }
        app.globalShortcutRegistered = hotKey.isRegistered
        stage.shortcutHint = hotKey.isRegistered ? GlobalHotKey.display : nil
        if !settings.collapsesWhenIdle { idleTask?.cancel(); unshrink() }
        if !settings.nudgesWhenIgnored { nudgeTask?.cancel() }
        if stage.machine.isVisible, dragStart == nil { positionPanel() }
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

    private func targetScreen() -> NSScreen? {
        switch app.settings.screen {
        case .followMouse:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        case .primary:
            return NSScreen.screens.first
        }
    }

    private var panelContentSize: CGSize {
        PanelPlacement.contentSize(
            characterSize: app.settings.characterSize.points,
            bubbleSize: CGSize(width: SpeechBubble.width, height: 400),
            edge: app.settings.edge
        )
    }

    private func positionPanel() {
        guard let screen = targetScreen() else { return }
        screenFrame = screen.frame
        visibleFrame = screen.visibleFrame
        place(at: app.settings.edgePosition)
        tracker.update()
    }

    private func place(at position: Double) {
        guard let visible = visibleFrame else { return }
        let settings = app.settings
        stage.growsDown = PanelPlacement.growsDown(edge: settings.edge, position: position)
        let frame = PanelPlacement.frame(
            contentSize: panelContentSize,
            edge: settings.edge,
            position: position,
            visibleFrame: visible,
            characterSize: CGFloat(settings.characterSize.points)
        )
        panel.setFrame(frame, display: true)
    }

    /// With "Screen with the pointer", the character hops to the display the
    /// pointer has moved to, once the pointer settles there.
    private func pointerMoved() {
        guard app.settings.screen == .followMouse, stage.phase == .presented, !stage.isExpanded,
              dragStart == nil, !isHopping
        else { return }
        guard let screen = targetScreen(), screen.frame != screenFrame else {
            hopTask?.cancel()
            hopTask = nil
            return
        }
        guard hopTask == nil else { return }
        hopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self, !Task.isCancelled else { return }
            self.hopTask = nil
            guard self.stage.phase == .presented, !self.stage.isExpanded, self.targetScreen()?.frame != self.screenFrame else { return }
            self.hopToPointerScreen()
        }
    }

    private func hopToPointerScreen() {
        isHopping = true
        let showBubble = !stage.isShrunk
        withAnimation(bubbleAnimation) { stage.bubbleVisible = false }
        animator.run(plan.exit, on: stage) { [weak self] in
            guard let self else { return }
            guard self.stage.phase == .presented else { self.isHopping = false; return }
            self.positionPanel()
            AnimationCoordinator.set(self.plan.initial, on: self.stage)
            self.animator.run(self.plan.entrance, on: self.stage) { [weak self] in
                guard let self else { return }
                self.isHopping = false
                if showBubble, self.stage.phase == .presented {
                    withAnimation(self.bubbleAnimation) { self.stage.bubbleVisible = true }
                }
            }
        }
    }

    // MARK: Global shortcut

    /// Control-Option-B opens the current request, or closes it again.
    private func hotKeyPressed() {
        guard stage.request != nil, stage.machine.isVisible, stage.phase != .exiting else { return }
        if stage.isExpanded { collapse() } else { expand() }
    }

    // MARK: StageActions

    func expand() {
        guard stage.request != nil else { return }
        idleTask?.cancel()
        stage.isShrunk = false
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
        scheduleIdleCollapse()
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

    func focus(_ id: RequestID) {
        app.focus(id)
    }

    func dragChanged() {
        let mouse = NSEvent.mouseLocation
        guard let visible = visibleFrame else { return }
        let edge = app.settings.edge
        let characterSize = CGFloat(app.settings.characterSize.points)
        if dragStart == nil {
            let anchor = PanelPlacement.dragAnchor(of: panel.frame, edge: edge, growsDown: stage.growsDown, characterSize: characterSize)
            dragStart = (mouse, anchor)
            idleTask?.cancel()
            tracker.isDragging = true
        }
        guard let start = dragStart else { return }
        let delta = edge == .bottom ? mouse.x - start.mouse.x : mouse.y - start.mouse.y
        let position = PanelPlacement.position(
            forDragAnchor: start.anchor + delta,
            edge: edge,
            contentSize: panelContentSize,
            visibleFrame: visible,
            characterSize: characterSize
        )
        dragPosition = position
        // The bubble flips sides as the character crosses the middle.
        withAnimation(stage.reduceMotion ? nil : .easeInOut(duration: 0.2)) { place(at: position) }
    }

    func dragEnded() {
        tracker.isDragging = false
        let position = dragPosition
        dragStart = nil
        dragPosition = nil
        // Saved like the Settings slider; repositioning lands on the same spot.
        if let position { app.settings.edgePosition = position }
        tracker.update()
        if stage.phase == .presented, !stage.isExpanded { scheduleIdleCollapse() }
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

