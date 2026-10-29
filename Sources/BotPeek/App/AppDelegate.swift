#if canImport(AppKit)
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import BotPeekCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var characters: CharacterWindowManager!
    private var statusItem: StatusItemController!
    private var settingsWindow: HostedWindowController!
    private var onboardingWindow: HostedWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel()
        self.model = model
        GrokAvatarRenderer.shared.start(log: model.log)
        characters = CharacterWindowManager(app: model)
        model.onEvents = { [weak self] _ in self?.characters.sync() }

        settingsWindow = HostedWindowController(title: "BotPeek Settings") {
            AnyView(SettingsView(app: model))
        }
        onboardingWindow = HostedWindowController(title: "Welcome to BotPeek") { [weak self] in
            AnyView(OnboardingView(app: model) { self?.onboardingWindow.close() })
        }

        statusItem = StatusItemController(app: model)
        statusItem.openSettings = { [weak self] in self?.settingsWindow.show() }
        statusItem.openOnboarding = { [weak self] in self?.onboardingWindow.show() }
        statusItem.exportDiagnostics = { [weak self] in self?.exportDiagnostics() }

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.model.systemWillSleep() }
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.model.systemDidWake() }
        }

        model.start()
        if !model.settings.hasCompletedOnboarding {
            onboardingWindow.show()
        }
    }

    /// Opening BotPeek again (Finder, Spotlight) shows Settings, which is the
    /// way back when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func exportDiagnostics() {
        let report = model.diagnosticsReport()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "BotPeek-diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        NSApp.activate()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? report.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
#endif
