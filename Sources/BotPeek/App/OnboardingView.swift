#if canImport(AppKit)
import SwiftUI
import BotPeekCore

/// First-run walkthrough. Asks for Accessibility only when the user chooses to.
struct OnboardingView: View {
    @ObservedObject var app: AppModel
    var onFinish: () -> Void
    @State private var step = 0
    @State private var trusted = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: howItWorks
                default: permission
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(28)

            Divider()
            HStack {
                if step > 0 { Button("Back") { step -= 1 } }
                Spacer()
                if step < 2 {
                    Button("Continue") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Try the Demo") {
                        app.settings.demoMode = true
                        finish()
                    }
                    Button("Done") { finish() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 520, height: 430)
        .onReceive(timer) { _ in trusted = app.accessibilityTrusted }
        .onAppear { trusted = app.accessibilityTrusted }
    }

    private func finish() {
        app.settings.hasCompletedOnboarding = true
        onFinish()
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            HStack(spacing: -8) {
                BuiltInAvatar(shape: .cloud, color: AvatarColor.resolve("blue")).frame(width: 64, height: 64)
                BuiltInAvatar(shape: .sparkle, color: AvatarColor.resolve("purple")).frame(width: 64, height: 64)
                BuiltInAvatar(shape: .square, color: AvatarColor.resolve("green")).frame(width: 64, height: 64)
            }
            .accessibilityHidden(true)
            Text("Welcome to BotPeek")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text("Your bots visit you, not the other way around.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("When one of your Grok Bot bots needs an answer or an approval, it peeks out from the edge of your screen. Answer right there, and it hops back out of sight.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("An independent community project, not affiliated with Grok Bot, xAI or Cursor.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How it works").font(.title2.weight(.semibold))
            Point(icon: "eye", title: "Only when needed", text: "Characters appear only when a bot is waiting for you. Progress updates, unread messages and finished tasks never pop up.")
            Point(icon: "person.crop.circle", title: "Your real bots", text: "BotPeek reads each bot's name and avatar from Grok Bot's local data, read-only. It never reads credentials.")
            Point(icon: "lock", title: "Private by design", text: "No servers, analytics or tracking. Message text is never saved.")
            Point(icon: "menubar.rectangle", title: "Quiet in the menu bar", text: "Find pending requests, settings and demo mode in the menu bar icon.")
        }
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Replying from BotPeek").font(.title2.weight(.semibold))
            Text("To show a bot's full question and deliver your answer, BotPeek uses macOS Accessibility to read Grok Bot's window and press its buttons, just like VoiceOver. Without it, characters still appear and “Open in Grok Bot” always works.")
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Image(systemName: trusted ? "checkmark.circle.fill" : "hand.raised.circle")
                    .font(.title)
                    .foregroundStyle(trusted ? Color.green : Color.orange)
                VStack(alignment: .leading) {
                    Text(trusted ? "Accessibility access granted" : "Accessibility access not granted yet")
                        .font(.headline)
                    Text(trusted ? "You're all set." : "macOS will ask you to turn on BotPeek in Privacy & Security → Accessibility.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !trusted {
                Button("Grant Access…") { app.requestAccessibility() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct Point: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 26)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
#endif
