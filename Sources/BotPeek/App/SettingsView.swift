#if canImport(AppKit)
import AppKit
import ServiceManagement
import SwiftUI
import BotPeekCore

struct SettingsView: View {
    @ObservedObject var app: AppModel

    var body: some View {
        TabView {
            GeneralSettings(app: app)
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings(app: app)
                .tabItem { Label("Appearance", systemImage: "sparkles") }
            ConnectionSettings(app: app)
                .tabItem { Label("Connection", systemImage: "link") }
            PrivacySettings(app: app)
                .tabItem { Label("Privacy & About", systemImage: "hand.raised") }
        }
        .frame(width: 520, height: 470)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var app: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Show characters when bots need me", isOn: $app.settings.isEnabled)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Show menu bar icon", isOn: $app.settings.showMenuBarIcon)
                if !app.settings.showMenuBarIcon {
                    Text("To get back here, open BotPeek again from Applications or Spotlight.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Requests") {
                Picker("Snooze for", selection: $app.settings.snoozeMinutes) {
                    ForEach(BotPeekSettings.snoozeChoices, id: \.self) { minutes in
                        Text(minutes < 60 ? "\(minutes) minutes" : "\(minutes / 60) hour\(minutes == 60 ? "" : "s")").tag(minutes)
                    }
                }
                Toggle("Play a sound when a bot appears", isOn: $app.settings.soundsEnabled)
            }
            Section {
                Toggle("Approve or deny inline (experimental)", isOn: $app.settings.allowInlineApprovals)
                Text("Off by default: approvals open in Grok Bot so you can review them in full. When on, BotPeek shows exactly which button it will press and asks you to confirm.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Approvals")
            }
            Section("Demo") {
                Toggle("Demo mode (sample bots, not your Grok Bot)", isOn: $app.settings.demoMode)
                if app.settings.demoMode {
                    Button("Replay Demo") { app.replayDemo() }
                    Text("Type “\(DemoIntegration.failureKeyword)” in a demo reply to see how delivery errors look.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchError = nil
        } catch {
            launchError = "Couldn't change this. Move BotPeek to Applications and try again."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct AppearanceSettings: View {
    @ObservedObject var app: AppModel

    var body: some View {
        Form {
            Section("Position") {
                Picker("Screen edge", selection: $app.settings.edge) {
                    ForEach(ScreenEdge.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Position along edge") {
                    Slider(value: $app.settings.edgePosition, in: 0...1) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text(app.settings.edge == .bottom ? "Left" : "Bottom").font(.caption)
                    } maximumValueLabel: {
                        Text(app.settings.edge == .bottom ? "Right" : "Top").font(.caption)
                    }
                }
                Picker("Display", selection: $app.settings.screen) {
                    ForEach(ScreenChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section("Character") {
                Picker("Size", selection: $app.settings.characterSize) {
                    ForEach(CharacterSize.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Animation", selection: $app.settings.animationIntensity) {
                    ForEach(AnimationIntensity.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Reduce motion", isOn: $app.settings.reduceMotion)
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    Text("Reduce Motion is on in System Settings, so characters fade instead of moving.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Preview with Sample Bots") {
                    if app.settings.demoMode { app.replayDemo() } else { app.settings.demoMode = true }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ConnectionSettings: View {
    @ObservedObject var app: AppModel

    var body: some View {
        let health = app.health
        Form {
            Section("Grok Bot") {
                if health.isDemo {
                    Label("Demo mode is on. Turn it off in General to watch your real bots.", systemImage: "theatermasks")
                }
                StatusRow(title: "Installed", ok: health.grokBotInstalled, detail: health.grokBotVersion.map { "Version \($0)" })
                StatusRow(title: "Running", ok: health.grokBotRunning, detail: health.grokBotRunning ? nil : "Replies need Grok Bot open")
                StatusRow(title: "Signed in", ok: health.signedIn ?? false, detail: health.signedIn == nil ? "Unknown" : nil)
                rosterRow(health.roster)
                Button("Open Grok Bot") { app.openInGrokBot(nil) }
            }
            Section("Accessibility permission") {
                StatusRow(
                    title: "Accessibility",
                    ok: health.accessibility == .granted,
                    detail: health.accessibility == .granted ? "Granted" : "Needed to read questions and send replies"
                )
                if health.accessibility != .granted {
                    Button("Grant Access…") { app.requestAccessibility() }
                    Text("macOS asks once. BotPeek uses it only to read Grok Bot's window and to press its buttons or paste your reply. Unsigned builds need to be granted again after each update.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Avatars") {
                if health.photoAvatarsUnavailable > 0 {
                    Label("\(health.photoAvatarsUnavailable) uploaded avatar(s) couldn't be read from Grok Bot's cache; showing the bot's built-in shape instead.", systemImage: "photo.badge.exclamationmark")
                        .font(.caption)
                }
                if !health.unrecognizedAvatarShapes.isEmpty {
                    Label("Unrecognized avatar shapes: \(health.unrecognizedAvatarShapes.joined(separator: ", ")). These bots use a default outline in their own color.", systemImage: "questionmark.square.dashed")
                        .font(.caption)
                }
                if health.photoAvatarsUnavailable == 0 && health.unrecognizedAvatarShapes.isEmpty {
                    Text("Avatars come from Grok Bot's own data. Built-in shapes are redrawn by BotPeek in each bot's color; uploaded images are shown as-is.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Advanced") {
                Toggle("Also watch Grok Bot's sidebar for “waiting for you”", isOn: $app.settings.useSidebarSignal)
                Picker("Reply delivery", selection: $app.settings.deliveryMethod) {
                    ForEach(DeliveryMethod.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text("“Paste” briefly brings Grok Bot forward, pastes your reply, then restores your clipboard and the app you were using.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func rosterRow(_ roster: RosterHealth) -> some View {
        switch roster {
        case .ok(let count, let known):
            StatusRow(title: "Bots found", ok: true, detail: "\(count)")
            if !known {
                Label("Grok Bot's data format has changed since this BotPeek version was tested. Some details may be missing; please report it.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
            }
        case .failed(let error):
            StatusRow(title: "Bots found", ok: false, detail: error.userMessage)
        case .notApplicable:
            EmptyView()
        }
    }
}

private struct StatusRow: View {
    let title: String
    let ok: Bool
    var detail: String?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                if let detail { Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(ok ? Color.green : Color.orange)
                    .accessibilityLabel(ok ? "OK" : "Not available")
            }
        }
    }
}

private struct PrivacySettings: View {
    @ObservedObject var app: AppModel

    var body: some View {
        Form {
            Section("Privacy") {
                Label("No tracking, analytics, ads or BotPeek servers.", systemImage: "eye.slash")
                Label("Reads Grok Bot's local bot list read-only; never its credentials.", systemImage: "doc.text.magnifyingglass")
                Label("Message text stays in memory and is never saved.", systemImage: "memorychip")
                Label("Diagnostics contain events and errors only, never messages or bot names.", systemImage: "stethoscope")
            }
            Section("About") {
                LabeledContent("Version", value: AppInfo.version)
                Text("BotPeek is free, open-source software (MIT License). It is an independent community project and is not affiliated with, endorsed by or sponsored by Grok Bot, xAI, SpaceXAI, Anysphere or Cursor.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Link("Source code", destination: AppInfo.repositoryURL)
                    Link("Report an issue", destination: AppInfo.issuesURL)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Hosts SwiftUI content in a regular titled window.
@MainActor
final class HostedWindowController {
    private var window: NSWindow?
    private let title: String
    private let makeView: () -> AnyView

    init(title: String, makeView: @escaping () -> AnyView) {
        self.title = title
        self.makeView = makeView
    }

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: makeView())
            let window = NSWindow(contentViewController: controller)
            window.title = title
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}
#endif
