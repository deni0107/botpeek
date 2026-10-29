#if canImport(AppKit)
import AppKit
import SwiftUI
import BotPeekCore

/// Command-line entry points used by CI smoke tests and beta testers:
///
///     BotPeek.app/Contents/MacOS/BotPeek --version
///     BotPeek.app/Contents/MacOS/BotPeek --check
///     BotPeek.app/Contents/MacOS/BotPeek --render-avatars <folder>
///     BotPeek.app/Contents/MacOS/BotPeek --probe-open <bot log tag>
///
/// `--check` prints the integration status without names or message text.
/// `--render-avatars` writes every built-in shape, and each roster bot's
/// avatar (named by its log tag, not its name), as PNGs for a visual check.
/// `--probe-open` switches Grok Bot to one bot's conversation the way a reply
/// does and prints each step, to diagnose "opened a different conversation".
enum CommandLineTools {
    /// Returns an exit code if a command was handled, or `nil` to launch the app.
    @MainActor
    static func handle(_ arguments: [String]) -> Int32? {
        if arguments.contains("--version") {
            print("BotPeek \(AppInfo.version) (\(AppInfo.architecture))")
            return 0
        }
        if arguments.contains("--check") {
            let log = DiagnosticsLog()
            let integration = LiveGrokIntegration(log: log)
            let snapshot = integration.currentSnapshot(now: Date())
            let health = integration.health(now: Date())
            print("BotPeek \(AppInfo.version) (\(AppInfo.architecture)) on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
            print("Status: \(health.summary)")
            print("Grok Bot installed: \(health.grokBotInstalled)  version: \(health.grokBotVersion ?? "unknown")")
            print("Grok Bot running: \(health.grokBotRunning)  signed in: \(health.signedIn.map(String.init) ?? "unknown")")
            switch health.roster {
            case .ok(let count, let known):
                print("Roster: \(count) bots, schema v\(integration.lastRoster?.schemaVersion.map(String.init) ?? "?") (\(known ? "tested" : "UNTESTED"))")
            case .failed(let error):
                print("Roster: unavailable (\(error))")
            case .notApplicable:
                print("Roster: n/a")
            }
            print("Bots needing attention now: \(snapshot.attention.count) (complete read: \(snapshot.isComplete))")
            for observation in snapshot.attention {
                print("  - \(observation.bot.id.logTag): kind=\(observation.content.kind.rawValue) source=\(observation.source.rawValue) readable=\(observation.content.hasReadableContent)")
            }
            // macOS answers for the app that launched this process (often Terminal),
            // not for BotPeek.app opened from Finder.
            print("Accessibility permission: \(health.accessibility.rawValue) (for this process; when run from Terminal, Terminal's permission)")
            print("Uploaded avatars unavailable: \(health.photoAvatarsUnavailable)")
            print("Unrecognized avatar shapes: \(health.unrecognizedAvatarShapes.count)")
            GrokAvatarRenderer.shared.loadNow(log: log)
            print("Avatar artwork: \(GrokAvatarRenderer.shared.state)")
            return 0
        }
        if let index = arguments.firstIndex(of: "--probe-open") {
            guard index + 1 < arguments.count else {
                print("usage: BotPeek --probe-open <bot log tag from --check, e.g. bot#a9bbc0>")
                return 2
            }
            return probeOpen(tag: arguments[index + 1])
        }
        if let index = arguments.firstIndex(of: "--render-avatars") {
            guard index + 1 < arguments.count else {
                print("usage: BotPeek --render-avatars <folder>")
                return 2
            }
            return renderAvatars(to: URL(fileURLWithPath: arguments[index + 1], isDirectory: true))
        }
        return nil
    }

    @MainActor
    private static func probeOpen(tag: String) -> Int32 {
        let log = DiagnosticsLog()
        let integration = LiveGrokIntegration(log: log)
        _ = integration.currentSnapshot(now: Date())
        let roster = integration.rosterIdentities
        guard let bot = roster.first(where: { $0.id.logTag == tag }) else {
            print("No bot with log tag \(tag). Tags: \(roster.map(\.id.logTag).joined(separator: " "))")
            return 2
        }
        var outcome = "unfinished"
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let (conversation, _) = try await integration.driver.openConversation(for: bot, roster: roster)
                outcome = "opened; open question: \(conversation.openQuestion != nil), composer: \(conversation.composerNodeID != nil)"
            } catch {
                outcome = "failed: \(error)"
            }
            done.signal()
        }
        while done.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        for entry in log.allEntries where entry.category == "ax" {
            print("[\(entry.level.rawValue)] \(entry.message)")
        }
        print("Result: \(outcome)")
        return outcome.hasPrefix("opened") ? 0 : 1
    }

    @MainActor
    private static func renderAvatars(to folder: URL) -> Int32 {
        let log = DiagnosticsLog()
        let renderer = GrokAvatarRenderer.shared
        renderer.loadNow(log: log)
        print("Avatar artwork: \(renderer.state)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var jobs: [(String, AvatarSource)] = AvatarShape.allCases.map { ("shape-\($0.rawValue)", .builtIn(shape: $0, color: .defaultColor)) }
        jobs += ["happy-clover": .builtIn(shape: .clover, color: AvatarColor.resolve("violet"))].map { ($0.key, $0.value) }
        let integration = LiveGrokIntegration(log: log)
        _ = integration.currentSnapshot(now: Date())
        for bot in integration.lastRoster?.bots ?? [] {
            jobs.append(("bot-\(bot.id.logTag.replacingOccurrences(of: "#", with: ""))-\(bot.identity.avatar.shape.grokName)-\(bot.identity.avatar.color.name)", integration.avatarSource(for: bot.identity)))
        }
        var written = 0
        for (name, source) in jobs {
            let view = BotAvatarView(source: source, size: 128, isHappy: name.hasPrefix("happy"))
            let renderer = ImageRenderer(content: view.padding(12))
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { continue }
            if (try? png.write(to: folder.appendingPathComponent(name + ".png"))) != nil { written += 1 }
        }
        print("Wrote \(written) of \(jobs.count) avatars to \(folder.path)")
        return written == jobs.count ? 0 : 1
    }
}
#endif
