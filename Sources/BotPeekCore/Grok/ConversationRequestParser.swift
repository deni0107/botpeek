import Foundation

/// Finds a request still waiting for the user in a bot's cached conversation
/// (`<account>.transcript.replicas.<bot id>`).
///
/// Grok Bot 0.78 does not set the roster's `awaitingUserResponse` for questions
/// asked in chat. They are stored as conversation entries instead:
/// ```json
/// { "kind": "send-message", "id": "t3s0", "timestampMs": 1730000000000,
///   "message": { "type": "widget",
///     "widget": { "prompt": "…", "options": [ { "label": "…", "value": "…" } ],
///                 "allowCustom": true, "multiSelect": false } } }
/// ```
/// Grok Bot marks what happened to a question on the entry itself:
/// `respondedValue` (answered), `widgetSkipped` (the user wrote something else)
/// or `widgetDismissed`. Approvals (`auto-review-approval`) carry a `status`,
/// forms (`user-form`) a `formResolution`.
///
/// A request counts as open only when it is the latest turn in the
/// conversation, so an old question the user moved past never pops up.
public enum ConversationRequestParser {
    public struct OpenRequest: Equatable, Sendable {
        public var fingerprint: String
        public var content: AttentionContent
    }

    static let widgetResolutionKeys = ["respondedValue", "widgetSkipped", "widgetDismissed"]
    static let formResolutionKeys = ["formResolution", "formSubmissionEffect"]
    static let pendingApprovalStatuses = ["pending", "open", "requested", "awaiting", "waiting"]

    public static func openRequest(in data: Data) -> OpenRequest? {
        guard let root = try? JSONValue.parse(data),
              let entries = root["value"]?["entries"]?.arrayValue ?? root["entries"]?.arrayValue
        else { return nil }
        return openRequest(entries: entries)
    }

    public static func openRequest(entries: [JSONValue]) -> OpenRequest? {
        guard let last = entries.last(where: isTurn),
              last["kind"]?.stringValue == "send-message",
              let message = last["message"]
        else { return nil }

        let content: AttentionContent?
        switch message["type"]?.stringValue {
        case "widget":
            guard !isResolved(last, keys: widgetResolutionKeys), let widget = message["widget"] else { return nil }
            content = widgetContent(widget)
        case "auto-review-approval":
            let status = message["approval"]?["status"]?.stringValue?.lowercased() ?? ""
            guard pendingApprovalStatuses.contains(where: status.hasPrefix) else { return nil }
            let approval = message["approval"]
            content = AttentionContent(
                kind: .approval,
                prompt: (approval?["summary"]?.stringValue ?? approval?["reason"]?.stringValue).flatMap(AwaitingRequestParser.clean),
                source: .conversation,
                grokBotOnlyReason: "Review this approval in Grok Bot."
            )
        case "user-form":
            guard !isResolved(last, keys: formResolutionKeys) else { return nil }
            // Forms can ask for passwords and codes: those never pass through BotPeek.
            content = AttentionContent(
                kind: .handoff,
                prompt: message["formRequest"]?["title"]?.stringValue.flatMap(AwaitingRequestParser.clean),
                source: .conversation,
                grokBotOnlyReason: "Fill this in securely in Grok Bot."
            )
        default:
            content = nil
        }
        guard let content else { return nil }

        let identity = [last["id"]?.identifierString ?? "", last["timestampMs"]?.identifierString ?? ""]
        return OpenRequest(fingerprint: StableHash.fnv1a(identity.joined(separator: "|")), content: content)
    }

    /// Entries that move the conversation on: the bot posting to the user, or
    /// the user writing or attaching something. Messages between bots don't count.
    static func isTurn(_ entry: JSONValue) -> Bool {
        switch entry["kind"]?.stringValue {
        case "send-message", "user-attachment":
            return true
        case "message":
            return entry["role"]?.stringValue == "user" && (entry["fromAgent"]?.isEmptySignal ?? true)
        default:
            return false
        }
    }

    static func isResolved(_ entry: JSONValue, keys: [String]) -> Bool {
        keys.contains { entry[$0].map { !$0.isEmptySignal } ?? false }
    }

    static func widgetContent(_ widget: JSONValue) -> AttentionContent {
        let prompt = widget["prompt"]?.stringValue.flatMap(AwaitingRequestParser.clean)
        let choices = AwaitingRequestParser.dedupe(Array(
            (widget["options"]?.arrayValue ?? []).compactMap(AwaitingRequestParser.choice(from:))
                .prefix(AwaitingRequestParser.maximumChoices)
        ))
        // One button press can't answer a multi-select or multi-step widget,
        // so show the options and take a typed answer instead.
        let isMultiple = widget["multiSelect"]?.boolValue == true || widget["steps"]?.arrayValue?.isEmpty == false
        if isMultiple || choices.isEmpty {
            let list = choices.map { "• " + $0.label }.joined(separator: "\n")
            let text = [prompt, list.isEmpty ? nil : list].compactMap { $0 }.joined(separator: "\n\n")
            return AttentionContent(kind: .question, prompt: text.isEmpty ? nil : text, source: .conversation)
        }
        let kind: AttentionKind = ApprovalHeuristics.looksLikeApproval(choices) ? .approval : .choice
        return AttentionContent(kind: kind, prompt: prompt, choices: choices, source: .conversation)
    }
}

/// Reads bots' cached conversations, re-parsing a file only when it changes.
public final class ConversationStore: @unchecked Sendable {
    public static let maximumFileSize = 8 * 1_024 * 1_024
    static let transcriptKeyInfix = ".transcript.replicas."

    public let paths: GrokBotPaths
    private let lock = NSLock()
    private var cache: [URL: (modified: Date?, size: Int, request: ConversationRequestParser.OpenRequest?)] = [:]

    public init(paths: GrokBotPaths) {
        self.paths = paths
    }

    /// The conversation file for `botID` in the same account as `rosterFile`.
    public func fileURL(for botID: BotID, rosterFile: URL) -> URL? {
        guard let rosterKey = Base32.decodeKey(fileName: rosterFile.deletingPathExtension().lastPathComponent),
              rosterKey.hasSuffix(RosterStore.rosterKeySuffix)
        else { return nil }
        let account = rosterKey.dropLast(RosterStore.rosterKeySuffix.count)
        let key = account + Self.transcriptKeyInfix + botID.rawValue
        // Base32 output is [a-z2-7] only, so bot ids can't escape the folder.
        return paths.persistenceDirectory.appendingPathComponent(Base32.encode(Data(key.utf8)) + ".blob")
    }

    /// Open requests by bot. Bots without a conversation file are left out.
    public func openRequests(for bots: [BotID], rosterFile: URL) -> [BotID: ConversationRequestParser.OpenRequest] {
        var result: [BotID: ConversationRequestParser.OpenRequest] = [:]
        var seen = Set<URL>()
        for bot in bots {
            guard let url = fileURL(for: bot, rosterFile: rosterFile) else { continue }
            seen.insert(url)
            if let request = openRequest(at: url) { result[bot] = request }
        }
        lock.lock()
        cache = cache.filter { seen.contains($0.key) }
        lock.unlock()
        return result
    }

    func openRequest(at url: URL) -> ConversationRequestParser.OpenRequest? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= Self.maximumFileSize
        else { return nil }
        let modified = values.contentModificationDate

        lock.lock()
        if let cached = cache[url], cached.modified == modified, cached.size == size {
            lock.unlock()
            return cached.request
        }
        lock.unlock()

        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        let request = ConversationRequestParser.openRequest(in: data)
        lock.lock()
        cache[url] = (modified, size, request)
        lock.unlock()
        return request
    }
}
