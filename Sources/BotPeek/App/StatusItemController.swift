#if canImport(AppKit)
import AppKit
import Combine
import BotPeekCore

/// The optional menu-bar icon: pending requests, quick toggles, settings.
/// The icon never animates; a small count appears only while bots wait.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let app: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellables = Set<AnyCancellable>()

    var openSettings: (() -> Void)?
    var openOnboarding: (() -> Void)?
    var exportDiagnostics: (() -> Void)?

    init(app: AppModel) {
        self.app = app
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.image = Self.icon
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.setAccessibilityLabel("BotPeek")

        app.$requests
            .combineLatest(app.$settings)
            .sink { [weak self] _ in Task { @MainActor in self?.updateButton() } }
            .store(in: &cancellables)
    }

    private func updateButton() {
        statusItem.isVisible = app.settings.showMenuBarIcon
        let waiting = app.requests.filter { request in
            if case .answered = request.status { return false }
            return true
        }.count
        statusItem.button?.title = waiting > 0 ? " \(waiting)" : ""
        statusItem.button?.appearsDisabled = !app.settings.isEnabled
        statusItem.button?.toolTip = waiting > 0
            ? "BotPeek: \(waiting) bot\(waiting == 1 ? "" : "s") waiting for you"
            : "BotPeek"
    }

    /// A small template glyph: a round character peeking past a vertical edge.
    static let icon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 13.5, y: 1.5, width: 2, height: 15), xRadius: 1, yRadius: 1).fill()
            let body = NSBezierPath(ovalIn: NSRect(x: 2, y: 3.5, width: 12, height: 11))
            body.fill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(roundedRect: NSRect(x: 5.4, y: 8, width: 1.8, height: 3.4), xRadius: 0.9, yRadius: 0.9).fill()
            NSBezierPath(roundedRect: NSRect(x: 8.8, y: 8, width: 1.8, height: 3.4), xRadius: 0.9, yRadius: 0.9).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "BotPeek"
        return image
    }()

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: app.health.summary, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let open = app.requests.filter { request in
            if case .answered = request.status { return false }
            return true
        }
        if open.isEmpty {
            let none = NSMenuItem(title: "No bots need you right now", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            let header = NSMenuItem(title: "Waiting for you", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for request in open {
                let item = NSMenuItem(title: title(for: request), action: #selector(showRequest(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = request.id.rawValue
                item.image = BotAvatarView.menuImage(source: app.avatarSource(for: request.bot))
                item.toolTip = request.content.displayPrompt
                menu.addItem(item)
            }
            let snooze = NSMenuItem(title: "Snooze All for \(app.settings.snoozeMinutes) Minutes", action: #selector(snoozeAll), keyEquivalent: "")
            snooze.target = self
            menu.addItem(snooze)
        }
        menu.addItem(.separator())

        let enabled = NSMenuItem(title: "Show Characters", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = app.settings.isEnabled ? .on : .off
        menu.addItem(enabled)

        let demo = NSMenuItem(title: "Demo Mode (Sample Bots)", action: #selector(toggleDemo), keyEquivalent: "")
        demo.target = self
        demo.state = app.settings.demoMode ? .on : .off
        menu.addItem(demo)
        if app.settings.demoMode {
            let replay = NSMenuItem(title: "Replay Demo", action: #selector(replayDemo), keyEquivalent: "")
            replay.target = self
            menu.addItem(replay)
        }
        menu.addItem(.separator())

        addItem(to: menu, "Open Grok Bot", #selector(openGrokBot))
        addItem(to: menu, "Settings…", #selector(showSettings), key: ",")
        addItem(to: menu, "Export Diagnostics…", #selector(exportLogs))
        addItem(to: menu, "Welcome & Permissions…", #selector(showOnboarding))
        menu.addItem(.separator())
        addItem(to: menu, "About BotPeek", #selector(showAbout))
        addItem(to: menu, "Quit BotPeek", #selector(quit), key: "q")
    }

    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    private func title(for request: AttentionRequest) -> String {
        var prompt = request.content.displayPrompt.replacingOccurrences(of: "\n", with: " ")
        if prompt.count > 48 { prompt = String(prompt.prefix(47)) + "…" }
        var title = "\(request.bot.name) — \(prompt)"
        switch request.status {
        case .snoozed: title += " (snoozed)"
        case .dismissed: title += " (dismissed)"
        case .replying: title += " (sending…)"
        default: break
        }
        return title
    }

    // MARK: Actions

    @objc private func showRequest(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let request = app.requests.first(where: { $0.id.rawValue == raw })
        else { return }
        app.show(request.id)
    }

    @objc private func snoozeAll() { app.snoozeAll() }
    @objc private func toggleEnabled() { app.settings.isEnabled.toggle() }
    @objc private func toggleDemo() { app.settings.demoMode.toggle() }
    @objc private func replayDemo() { app.replayDemo() }
    @objc private func openGrokBot() { app.openInGrokBot(nil) }
    @objc private func showSettings() { openSettings?() }
    @objc private func exportLogs() { exportDiagnostics?() }
    @objc private func showOnboarding() { openOnboarding?() }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "BotPeek",
            .credits: NSAttributedString(
                string: "Free and open source (MIT). An independent community project, not affiliated with Grok Bot, xAI, SpaceXAI, Anysphere or Cursor.",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            ),
        ])
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
#endif
