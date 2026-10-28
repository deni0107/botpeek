#if canImport(AppKit)
import AppKit
import BotPeekCore

/// Command-line entry points used by CI smoke tests and beta testers:
///
///     BotPeek.app/Contents/MacOS/BotPeek --version
///     BotPeek.app/Contents/MacOS/BotPeek --check
///
/// `--check` prints the integration status without names or message text.
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
            print("Accessibility permission: \(health.accessibility.rawValue)")
            print("Uploaded avatars unavailable: \(health.photoAvatarsUnavailable)")
            print("Unrecognized avatar shapes: \(health.unrecognizedAvatarShapes.count)")
            return 0
        }
        return nil
    }
}
#endif
