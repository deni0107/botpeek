import Foundation
@testable import BotPeekCore

enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: nil)
        else { throw CocoaError(.fileNoSuchFile) }
        return try Data(contentsOf: url)
    }
}

func identity(_ id: String, _ name: String, shape: String? = nil, color: String? = nil) -> BotIdentity {
    BotIdentity(id: BotID(id), name: name, avatar: AvatarDescriptor(rawShape: shape, rawColor: color))
}

func observation(_ bot: BotIdentity, _ fingerprint: String, prompt: String? = "Question?", choices: [String] = [], source: AttentionSource = .roster) -> AttentionObservation {
    AttentionObservation(
        bot: bot,
        fingerprint: fingerprint,
        content: AttentionContent(
            kind: choices.isEmpty ? .question : .choice,
            prompt: prompt,
            choices: choices.map { AttentionChoice(label: $0) },
            source: .roster
        ),
        source: source
    )
}

func snapshot(at seconds: Double, bots: [BotIdentity], attention: [AttentionObservation], complete: Bool = true) -> StatusSnapshot {
    StatusSnapshot(observedAt: Date(timeIntervalSince1970: seconds), bots: bots, attention: attention, isComplete: complete)
}

func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }

/// A temporary fake `~/Library/Application Support/Grok Bot`.
final class TemporaryGrokFolder {
    let root: URL
    let paths: GrokBotPaths

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("botpeek-tests-" + UUID().uuidString, isDirectory: true)
        paths = GrokBotPaths(supportDirectory: root)
        try FileManager.default.createDirectory(at: paths.persistenceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.avatarsDirectory, withIntermediateDirectories: true)
    }

    @discardableResult
    func writeBlob(key: String, data: Data, modified: Date? = nil) throws -> URL {
        let name = Base32.encode(Data(key.utf8)) + ".blob"
        let url = paths.persistenceDirectory.appendingPathComponent(name)
        try data.write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }

    func writeAvatar(key: String, bytes: Int = 64) throws {
        try Data(repeating: 0xAB, count: bytes).write(to: paths.avatarsDirectory.appendingPathComponent(key))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }
}

/// A scripted reply service that records exactly what was sent where.
final class RecordingReplyService: ReplyService {
    enum Outcome {
        case verified
        case unverified
        case fail(ReplyError)
    }

    var capabilities = ReplyCapabilities(text: true, choices: true, approvals: true)
    var outcomes: [Outcome] = []
    private(set) var deliveries: [(reply: Reply, target: ReplyTarget)] = []

    func deliver(_ reply: Reply, to target: ReplyTarget) async throws -> DeliveryReceipt {
        deliveries.append((reply, target))
        let outcome = outcomes.isEmpty ? .verified : outcomes.removeFirst()
        switch outcome {
        case .verified: return DeliveryReceipt(verified: true, completedAt: date(1_000), method: "test")
        case .unverified: return DeliveryReceipt(verified: false, completedAt: date(1_000), method: "test")
        case .fail(let error): throw error
        }
    }
}

// MARK: - Accessibility tree builders

final class AXTreeBuilder {
    private var nextID = 0

    func node(_ role: String, title: String? = nil, desc: String? = nil, value: String? = nil, _ children: [AXNodeSnapshot] = []) -> AXNodeSnapshot {
        nextID += 1
        return AXNodeSnapshot(id: nextID, role: role, title: title, axDescription: desc, value: value, children: children)
    }

    func text(_ value: String) -> AXNodeSnapshot { node("AXStaticText", value: value) }
    func button(_ label: String, _ children: [AXNodeSnapshot] = []) -> AXNodeSnapshot { node("AXButton", title: label, children) }

    func message(_ sender: String, _ time: String, _ texts: [String], buttons: [String] = [], dismiss: Bool = false) -> AXNodeSnapshot {
        var children: [AXNodeSnapshot] = [text(sender)] + texts.map(text) + [text(time)]
        if !buttons.isEmpty || dismiss {
            var questionChildren = buttons.map { button($0, [text($0)]) }
            if dismiss { questionChildren.append(button("Dismiss question")) }
            children.append(node("AXGroup", questionChildren))
        }
        return node("AXGroup", title: "\(sender) \(time)", children)
    }

    /// A Grok Bot-like window with a sidebar, heading, transcript and composer.
    func window(sidebar: [String], heading: String?, messages: [AXNodeSnapshot], composer: Bool = true) -> AXNodeSnapshot {
        var main: [AXNodeSnapshot] = []
        if let heading { main.append(node("AXHeading", desc: heading)) }
        main.append(node("AXGroup", desc: "Conversation transcript", [node("AXGroup", messages)]))
        if composer { main.append(node("AXTextArea", desc: "Prompt")) }
        let sidebarButtons = (["Toggle compact sidebar", "New chat"] + sidebar).map { button($0) }
        return node("AXWindow", title: "Grok Bot", [
            node("AXList", desc: "Bots", sidebarButtons),
            node("AXGroup", main),
        ])
    }
}
