#if canImport(AppKit)
import AppKit

@MainActor
enum BotPeekMain {
    /// `NSApplication.delegate` is weak; keep the delegate alive here.
    static var delegate: AppDelegate?

    static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        // A background utility: no Dock icon, no main menu, never steals focus on launch.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

MainActor.assumeIsolated {
    if let code = CommandLineTools.handle(CommandLine.arguments) {
        exit(code)
    }
    BotPeekMain.run()
}
#else
print("BotPeek is a macOS app. On this platform only BotPeekCore and its tests are built.")
#endif
