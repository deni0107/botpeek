#if canImport(AppKit)
import AppKit
import ApplicationServices
import BotPeekCore

/// Reads and drives Grok Bot's window through the macOS Accessibility API,
/// the same interface VoiceOver uses.
///
/// Approach adapted from grok-bot-mcp (Copyright (c) 2026 Ryan Thomas, MIT):
/// open a bot by pressing its sidebar button, confirm the conversation heading,
/// press choice buttons directly, and type replies by pasting into the
/// "Prompt" box while preserving the clipboard. BotPeek adds strict identity
/// matching, draft protection, focus restoration and delivery verification.
///
/// Methods are `nonisolated async`, so the Accessibility IPC runs off the main
/// thread; anything touching AppKit state hops to the main actor.
final class GrokAccessibilityDriver: @unchecked Sendable {
    private let log: DiagnosticsLog
    private var enabledPIDs = Set<pid_t>()
    private let lock = NSLock()

    init(log: DiagnosticsLog) {
        self.log = log
    }

    // MARK: Permission and process

    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    var runningApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: GrokBotApp.bundleIdentifier).first
    }

    private func prepare() throws -> pid_t {
        guard isTrusted else { throw ReplyError.accessibilityPermissionMissing }
        guard let app = runningApp else { throw ReplyError.grokBotNotRunning }
        let pid = app.processIdentifier
        lock.lock()
        let isNew = enabledPIDs.insert(pid).inserted
        lock.unlock()
        if isNew { AXTree.enableManualAccessibility(pid: pid) }
        return pid
    }

    // MARK: Reading

    /// Snapshots Grok Bot's main window, retrying while Chromium builds its tree.
    func windowSnapshot() async throws -> AXSnapshot {
        let pid = try prepare()
        for attempt in 0..<4 {
            if let window = AXTree.windows(of: pid).first {
                let snapshot = AXTree.snapshot(window)
                if SidebarParser.findSidebar(in: snapshot.root) != nil { return snapshot }
            }
            if attempt == 0 { AXTree.enableManualAccessibility(pid: pid) }
            try await Task.sleep(nanoseconds: 400_000_000)
        }
        throw ReplyError.grokBotWindowUnavailable
    }

    /// Sidebar buttons, or `nil` when they can't be read right now.
    func sidebarEntries() async -> [SidebarEntry]? {
        guard let snapshot = try? await windowSnapshot() else { return nil }
        return SidebarParser.entries(in: snapshot.root)
    }

    /// The conversation currently open, without navigating anywhere.
    func currentConversation() async throws -> (ConversationSnapshot, AXSnapshot) {
        let snapshot = try await windowSnapshot()
        return (TranscriptParser.parse(window: snapshot.root), snapshot)
    }

    /// Opens `bot`'s existing conversation by pressing its sidebar button and
    /// confirms the heading matches. Never creates bots or conversations.
    func openConversation(for bot: BotIdentity, roster: [BotIdentity]) async throws -> (ConversationSnapshot, AXSnapshot) {
        var snapshot = try await windowSnapshot()
        var conversation = TranscriptParser.parse(window: snapshot.root)
        if conversation.heading == bot.name { return (conversation, snapshot) }

        guard let entries = SidebarParser.entries(in: snapshot.root) else { throw ReplyError.grokBotWindowUnavailable }
        let entry: SidebarEntry
        switch BotIdentityMatcher.match(bot: bot, roster: roster, sidebar: entries) {
        case .unique(let match): entry = match
        case .ambiguous: throw ReplyError.ambiguousBot
        case .notFound: throw ReplyError.botNotFound
        }
        guard let button = snapshot.element(entry.nodeID), AXTree.press(button) else {
            throw ReplyError.botNotFound
        }
        log.record(.info, "ax", "Opened conversation for \(bot.id.logTag)")

        for _ in 0..<24 {
            try await Task.sleep(nanoseconds: 250_000_000)
            snapshot = try await windowSnapshot()
            conversation = TranscriptParser.parse(window: snapshot.root)
            if conversation.heading == bot.name {
                // Let the transcript finish rendering.
                try await Task.sleep(nanoseconds: 400_000_000)
                snapshot = try await windowSnapshot()
                conversation = TranscriptParser.parse(window: snapshot.root)
                guard conversation.heading == bot.name else { throw ReplyError.conversationMismatch }
                return (conversation, snapshot)
            }
        }
        throw ReplyError.conversationMismatch
    }

    // MARK: Choices

    func pressChoice(_ label: String, for bot: BotIdentity, roster: [BotIdentity]) async throws -> DeliveryReceipt {
        let (before, snapshot) = try await openConversation(for: bot, roster: roster)
        guard let question = before.openQuestion else { throw ReplyError.questionNotFound }
        guard let option = question.options.first(where: { $0.label == label }),
              let element = snapshot.element(option.nodeID)
        else { throw ReplyError.choiceNotOffered }

        guard AXTree.press(element) else { throw ReplyError.choiceNotOffered }
        log.record(.info, "ax", "Pressed a choice for \(bot.id.logTag)")
        // From here on, never retry: the press reached Grok Bot.
        return await verify(method: "accessibility-press") { after in
            after.heading == bot.name && DeliveryVerifier.choiceDelivered(label, before: before, after: after)
        }
    }

    // MARK: Text

    func sendText(_ text: String, to bot: BotIdentity, roster: [BotIdentity], method: DeliveryMethod) async throws -> DeliveryReceipt {
        let (before, snapshot) = try await openConversation(for: bot, roster: roster)
        guard let composer = snapshot.element(before.composerNodeID) else { throw ReplyError.composerNotFound }

        // Never overwrite something the user was typing in Grok Bot.
        if let draft = AXTree.string(composer, kAXValueAttribute),
           !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ReplyError.other("Grok Bot has an unsent draft in this conversation. BotPeek won't overwrite it.")
        }

        switch method {
        case .backgroundExperimental:
            return try await sendInBackground(text, composer: composer, snapshot: snapshot, before: before, bot: bot)
        case .pasteAndReturn:
            return try await sendByPasting(text, composer: composer, before: before, bot: bot)
        }
    }

    private func sendInBackground(_ text: String, composer: AXUIElement, snapshot: AXSnapshot, before: ConversationSnapshot, bot: BotIdentity) async throws -> DeliveryReceipt {
        guard AXTree.setValue(composer, text),
              AXTree.string(composer, kAXValueAttribute) == text,
              let send = snapshot.element(before.sendButtonNodeID)
        else {
            _ = AXTree.setValue(composer, "")
            throw ReplyError.other("Background sending isn't supported by this Grok Bot version. Switch Delivery to “Paste into Grok Bot” in Settings.")
        }
        guard AXTree.press(send) else { throw ReplyError.composerNotFound }
        log.record(.info, "ax", "Sent text in background to \(bot.id.logTag)")
        return await verify(method: "accessibility-value") { after in
            after.heading == bot.name && DeliveryVerifier.textDelivered(text, before: before, after: after)
        }
    }

    private func sendByPasting(_ text: String, composer: AXUIElement, before: ConversationSnapshot, bot: BotIdentity) async throws -> DeliveryReceipt {
        guard let grok = runningApp else { throw ReplyError.grokBotNotRunning }
        let previous = await MainActor.run { FocusKeeper.capture(excluding: grok) }

        await MainActor.run { _ = grok.activate(options: []) }
        try await Task.sleep(nanoseconds: 350_000_000)
        AXTree.focus(composer)
        try await Task.sleep(nanoseconds: 200_000_000)

        // Only type if Grok Bot really is in front: keystrokes go to the
        // frontmost app, and they must never land anywhere else.
        let isFront = await MainActor.run {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == grok.processIdentifier
        }
        guard isFront else {
            await MainActor.run { previous?.restore() }
            throw ReplyError.grokBotWindowUnavailable
        }

        let clipboard = await MainActor.run { ClipboardGuard.save() }
        await MainActor.run { ClipboardGuard.put(text) }
        KeyboardEvents.paste()
        try? await Task.sleep(nanoseconds: 400_000_000)
        KeyboardEvents.pressReturn()
        log.record(.info, "ax", "Pasted text and pressed Return for \(bot.id.logTag)")
        try? await Task.sleep(nanoseconds: 300_000_000)
        await MainActor.run {
            ClipboardGuard.restore(clipboard)
            previous?.restore()
        }

        return await verify(method: "paste-and-return") { after in
            after.heading == bot.name && DeliveryVerifier.textDelivered(text, before: before, after: after)
        }
    }

    // MARK: Verification

    /// Polls the conversation until `check` passes, for up to ~7 seconds.
    private func verify(method: String, _ check: (ConversationSnapshot) -> Bool) async -> DeliveryReceipt {
        for _ in 0..<28 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if let current = try? await currentConversation(), check(current.0) {
                return DeliveryReceipt(verified: true, completedAt: Date(), method: method)
            }
        }
        log.record(.warning, "ax", "Could not verify delivery (\(method))")
        return DeliveryReceipt(verified: false, completedAt: Date(), method: method)
    }

    // MARK: Fallback

    /// Brings Grok Bot forward, opening the bot's conversation when possible.
    func open(bot: BotIdentity?, roster: [BotIdentity]) async {
        if let app = runningApp {
            await MainActor.run { _ = app.activate(options: [.activateAllWindows]) }
            if let bot, isTrusted {
                _ = try? await openConversation(for: bot, roster: roster)
            }
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: GrokBotApp.bundleIdentifier) {
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            await MainActor.run { _ = NSWorkspace.shared.open(GrokBotApp.downloadURL) }
        }
    }
}

// MARK: - Focus, clipboard and keyboard helpers

/// Remembers the app the user was in, to return to it afterwards.
@MainActor
struct FocusKeeper {
    let app: NSRunningApplication

    static func capture(excluding other: NSRunningApplication) -> FocusKeeper? {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != other.processIdentifier,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        return FocusKeeper(app: front)
    }

    func restore() {
        guard !app.isTerminated else { return }
        _ = app.activate(options: [])
    }
}

/// Saves and restores every item and type on the general pasteboard.
@MainActor
enum ClipboardGuard {
    typealias Saved = [[(NSPasteboard.PasteboardType, Data)]]

    static func save() -> Saved {
        let pasteboard = NSPasteboard.general
        return (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    static func put(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Ask clipboard managers not to record the reply.
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
    }

    static func restore(_ saved: Saved) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let items: [NSPasteboardItem] = saved.compactMap { entries in
            guard !entries.isEmpty else { return nil }
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}

enum KeyboardEvents {
    private static let vKey: CGKeyCode = 9
    private static let returnKey: CGKeyCode = 36

    static func paste() {
        post(vKey, flags: .maskCommand)
    }

    static func pressReturn() {
        post(returnKey, flags: [])
    }

    private static func post(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
#endif
