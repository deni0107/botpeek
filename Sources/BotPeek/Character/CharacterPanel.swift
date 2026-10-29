#if canImport(AppKit)
import AppKit
import SwiftUI

/// A transparent, borderless panel that floats above ordinary windows,
/// follows the user across Spaces and full-screen apps, and never activates
/// BotPeek: the app the user was in stays in front.
final class CharacterPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        title = "BotPeek"
        setAccessibilitySubrole(.floatingWindow)
    }

    // Key status is needed only to type a reply; it never activates the app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Makes the transparent parts of the panel click-through.
///
/// SwiftUI reports the frames of the character and the bubble; whenever the
/// pointer moves, the panel accepts mouse events only while the pointer is
/// over one of them. Mouse-move monitoring needs no special permission.
@MainActor
final class ClickThroughTracker {
    private weak var panel: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// Called as the pointer moves anywhere while a character is shown.
    var onPointerMoved: (() -> Void)?
    /// While the character is dragged, the panel keeps the mouse.
    var isDragging = false
    /// Interactive rects in the panel's SwiftUI coordinate space (top-left origin).
    var interactiveRects: [CGRect] = [] {
        didSet { update() }
    }

    init(panel: NSPanel) {
        self.panel = panel
    }

    func start() {
        guard globalMonitor == nil else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            Task { @MainActor in
                self?.update()
                self?.onPointerMoved?()
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.update()
            return event
        }
        update()
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        panel?.ignoresMouseEvents = true
    }

    func update() {
        guard let panel, panel.isVisible, !isDragging else { return }
        let mouse = NSEvent.mouseLocation
        let frame = panel.frame
        let point = CGPoint(x: mouse.x - frame.minX, y: frame.height - (mouse.y - frame.minY))
        let inside = interactiveRects.contains { $0.insetBy(dx: -4, dy: -4).contains(point) }
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
    }
}

struct InteractiveRectsKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Marks this view as clickable in the otherwise click-through panel.
    func interactiveRegion() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: InteractiveRectsKey.self, value: [proxy.frame(in: .named(StageCoordinateSpace.name))])
            }
        )
    }
}

enum StageCoordinateSpace {
    static let name = "BotPeekStage"
}

/// Vibrant, behind-window material that stays active while BotPeek is in the background.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
#endif
