#if canImport(AppKit)
import AppKit
import JavaScriptCore
import Security
import BotPeekCore

/// Draws built-in avatars with Grok Bot's own avatar code, so characters look
/// exactly like they do in Grok Bot.
///
/// The code is read from the installed Grok Bot app at launch, only after its
/// code signature checks out, and runs in a bare JavaScriptCore context with
/// no file, network or DOM access. If anything about it doesn't match what
/// BotPeek expects, `image(…)` returns nil and BotPeek draws its own avatars.
@MainActor
final class GrokAvatarRenderer: ObservableObject {
    static let shared = GrokAvatarRenderer()

    enum State: Equatable {
        case idle
        case loading
        case ready(grokVersion: String?)
        case unavailable(String)
    }

    @Published private(set) var state: State = .idle
    private var context: JSContext?
    private var engine: JSValue?
    private var images: [String: NSImage] = [:]
    private var log: DiagnosticsLog?

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    func start(log: DiagnosticsLog) {
        guard state == .idle else { return }
        self.log = log
        state = .loading
        Task.detached(priority: .utility) {
            let prepared = Self.prepare()
            await MainActor.run { self.finish(prepared) }
        }
    }

    /// Loads on the calling thread, for command-line use where no run loop is running.
    func loadNow(log: DiagnosticsLog) {
        guard state == .idle else { return }
        self.log = log
        state = .loading
        finish(Self.prepare())
    }

    /// The avatar as Grok Bot draws it, or nil when Grok Bot's renderer is unavailable.
    func image(shape: AvatarShape, color: AvatarColor, isHappy: Bool) -> NSImage? {
        guard let engine, let context else { return nil }
        let key = "\(shape.grokName)|\(color.name)|\(color.rgb)|\(isHappy)"
        if let cached = images[key] { return cached }

        let id = "botpeek-\(images.count)"
        context.setObject(engine, forKeyedSubscript: "g" as NSString)
        defer { context.setObject(nil, forKeyedSubscript: "g" as NSString) }
        context.exception = nil
        let call = GrokAvatarScript.renderCall(shape: shape, color: color, isHappy: isHappy, id: id)
        guard let svg = context.evaluateScript(call)?.toString(), context.exception == nil, svg.hasPrefix("<svg") else {
            log?.record(.warning, "avatar", "Grok Bot renderer failed for shape \(shape.grokName)")
            context.exception = nil
            return nil
        }

        var stops = color.gradient
        if color.isRecognized,
           let pair = context.evaluateScript(GrokAvatarScript.gradientCall(color: color))?.toArray() as? [String],
           pair.count == 2, pair.allSatisfy(GrokAvatarScript.isHexColor),
           let from = AvatarColor.parseHexColor(pair[0]), let to = AvatarColor.parseHexColor(pair[1]) {
            stops = (from, to)
        }
        let full = GrokAvatarScript.injectGradient(
            into: svg, id: id, from: GrokAvatarScript.hex(stops.from), to: GrokAvatarScript.hex(stops.to)
        )
        guard let image = NSImage(data: Data(full.utf8)), image.isValid else {
            log?.record(.warning, "avatar", "Couldn't draw Grok Bot's SVG for shape \(shape.grokName)")
            return nil
        }
        images[key] = image
        return image
    }

    // MARK: - Loading

    private struct Prepared: Sendable {
        var script: GrokAvatarScript?
        var version: String?
        var failure: String?
    }

    nonisolated private static func prepare() -> Prepared {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: GrokBotApp.bundleIdentifier)
            ?? existing(URL(fileURLWithPath: "/Applications/Grok Bot.app"))
        else { return Prepared(failure: "Grok Bot isn't installed") }
        guard isGenuine(appURL) else { return Prepared(failure: "Grok Bot's code signature didn't verify") }
        let version = Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let asarURL = appURL.appendingPathComponent("Contents/Resources/app.asar")
        do {
            let archive = try AsarArchive(url: asarURL)
            return Prepared(script: try GrokAvatarScript.locate(in: archive), version: version)
        } catch {
            return Prepared(version: version, failure: "Grok Bot's avatar code wasn't found (\(error))")
        }
    }

    private func finish(_ prepared: Prepared) {
        guard let script = prepared.script else {
            state = .unavailable(prepared.failure ?? "unknown")
            log?.record(.info, "avatar", "Using BotPeek's own avatars: \(prepared.failure ?? "unknown")")
            return
        }
        guard let context = JSContext() else {
            state = .unavailable("JavaScriptCore unavailable")
            return
        }
        context.name = "BotPeek: Grok Bot avatars"
        let engine = context.evaluateScript(script.source, withSourceURL: URL(string: "grokbot-asar:///" + script.modulePath))
        if let exception = context.exception {
            state = .unavailable("Grok Bot's avatar code didn't load")
            log?.record(.warning, "avatar", "Grok Bot avatar script threw: \(exception.toString() ?? "?")")
            return
        }
        guard let engine, engine.isObject, engine.forProperty("render")?.isObject == true else {
            state = .unavailable("Grok Bot's avatar code has an unexpected shape")
            return
        }
        self.context = context
        self.engine = engine
        // Prove it end to end before claiming it works.
        guard image(shape: .classic, color: .defaultColor, isHappy: false) != nil,
              image(shape: .clover, color: .defaultColor, isHappy: false) != nil
        else {
            self.context = nil
            self.engine = nil
            images = [:]
            state = .unavailable("Grok Bot's avatar code didn't produce an image")
            log?.record(.warning, "avatar", "Grok Bot renderer self-test failed")
            return
        }
        state = .ready(grokVersion: prepared.version)
        log?.record(.info, "avatar", "Drawing avatars with Grok Bot \(prepared.version ?? "?")'s renderer")
    }

    nonisolated private static func existing(_ url: URL) -> URL? {
        FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Checks the bundle's signature, which also seals `app.asar`, so BotPeek
    /// never runs code from a modified or impostor Grok Bot.
    nonisolated private static func isGenuine(_ appURL: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var requirement: SecRequirement?
        let text = "anchor apple generic and identifier \"\(GrokBotApp.bundleIdentifier)\"" as CFString
        guard SecRequirementCreateWithString(text, [], &requirement) == errSecSuccess else { return false }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
#endif
