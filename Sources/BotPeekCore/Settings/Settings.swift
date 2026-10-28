import Foundation

public enum ScreenEdge: String, Codable, CaseIterable, Sendable {
    case right
    case bottom
    case left

    public var title: String {
        switch self {
        case .right: return "Right"
        case .bottom: return "Bottom"
        case .left: return "Left"
        }
    }
}

public enum ScreenChoice: String, Codable, CaseIterable, Sendable {
    /// The display that contains the mouse pointer.
    case followMouse
    /// The display with the menu bar.
    case primary

    public var title: String {
        switch self {
        case .followMouse: return "Screen with the pointer"
        case .primary: return "Main screen"
        }
    }
}

public enum AnimationIntensity: String, Codable, CaseIterable, Sendable {
    case lively
    case subtle
    case minimal

    public var title: String {
        switch self {
        case .lively: return "Lively"
        case .subtle: return "Subtle"
        case .minimal: return "Minimal"
        }
    }
}

public enum CharacterSize: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large

    public var points: Double {
        switch self {
        case .small: return 56
        case .medium: return 72
        case .large: return 92
        }
    }

    public var title: String { rawValue.capitalized }
}

public enum DeliveryMethod: String, Codable, CaseIterable, Sendable {
    /// Proven: focus Grok Bot's message box, paste, press Return, restore the
    /// clipboard and the previously active app.
    case pasteAndReturn
    /// Experimental: set the message box value through Accessibility and press
    /// the send button, without bringing Grok Bot forward.
    case backgroundExperimental

    public var title: String {
        switch self {
        case .pasteAndReturn: return "Paste into Grok Bot (reliable)"
        case .backgroundExperimental: return "Background (experimental)"
        }
    }
}

/// User preferences. Decoding tolerates missing keys so new settings never
/// reset existing ones.
public struct BotPeekSettings: Codable, Equatable, Sendable {
    public var isEnabled = true
    public var showMenuBarIcon = true
    public var edge: ScreenEdge = .right
    /// Position along the edge: 0 = bottom/left end, 1 = top/right end.
    public var edgePosition: Double = 0.3
    public var screen: ScreenChoice = .followMouse
    public var animationIntensity: AnimationIntensity = .lively
    public var characterSize: CharacterSize = .medium
    public var soundsEnabled = false
    /// Forces reduced motion even when the system setting is off.
    public var reduceMotion = false
    public var snoozeMinutes = 15
    /// Approve/deny inline. Off by default; approvals open in Grok Bot.
    public var allowInlineApprovals = false
    public var deliveryMethod: DeliveryMethod = .pasteAndReturn
    /// Also read "waiting for you" from Grok Bot's sidebar via Accessibility.
    public var useSidebarSignal = true
    public var demoMode = false
    public var hasCompletedOnboarding = false

    public init() {}

    public static let snoozeChoices = [5, 15, 30, 60, 120]

    enum CodingKeys: String, CodingKey {
        case isEnabled, showMenuBarIcon, edge, edgePosition, screen, animationIntensity, characterSize
        case soundsEnabled, reduceMotion, snoozeMinutes, allowInlineApprovals, deliveryMethod
        case useSidebarSignal, demoMode, hasCompletedOnboarding
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = BotPeekSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        isEnabled = value(.isEnabled, defaults.isEnabled)
        showMenuBarIcon = value(.showMenuBarIcon, defaults.showMenuBarIcon)
        edge = value(.edge, defaults.edge)
        edgePosition = min(max(value(.edgePosition, defaults.edgePosition), 0), 1)
        screen = value(.screen, defaults.screen)
        animationIntensity = value(.animationIntensity, defaults.animationIntensity)
        characterSize = value(.characterSize, defaults.characterSize)
        soundsEnabled = value(.soundsEnabled, defaults.soundsEnabled)
        reduceMotion = value(.reduceMotion, defaults.reduceMotion)
        snoozeMinutes = max(1, value(.snoozeMinutes, defaults.snoozeMinutes))
        allowInlineApprovals = value(.allowInlineApprovals, defaults.allowInlineApprovals)
        deliveryMethod = value(.deliveryMethod, defaults.deliveryMethod)
        useSidebarSignal = value(.useSidebarSignal, defaults.useSidebarSignal)
        demoMode = value(.demoMode, defaults.demoMode)
        hasCompletedOnboarding = value(.hasCompletedOnboarding, defaults.hasCompletedOnboarding)
    }
}

/// Minimal persistence interface, satisfied by `UserDefaults`.
public protocol KeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: KeyValueStore {}

public final class InMemoryKeyValueStore: KeyValueStore {
    private var values: [String: Data] = [:]
    public init() {}
    public func data(forKey key: String) -> Data? { values[key] }
    public func set(_ value: Any?, forKey key: String) { values[key] = value as? Data }
}

public final class SettingsStore {
    static let key = "settings.v1"
    private let store: KeyValueStore

    public init(store: KeyValueStore) {
        self.store = store
    }

    public func load() -> BotPeekSettings {
        guard let data = store.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(BotPeekSettings.self, from: data)
        else { return BotPeekSettings() }
        return settings
    }

    public func save(_ settings: BotPeekSettings) {
        store.set(try? JSONEncoder().encode(settings), forKey: Self.key)
    }
}

/// Persists dismissed request ids as hashes with dates. No content is stored.
public final class PersistentDismissedStore: DismissedRequestStore {
    static let key = "dismissedRequests.v1"
    private let store: KeyValueStore
    private var entries: [String: Double]

    public init(store: KeyValueStore) {
        self.store = store
        entries = store.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
    }

    private func hash(_ id: RequestID) -> String { StableHash.fnv1a(id.rawValue) }

    public func contains(_ id: RequestID) -> Bool { entries[hash(id)] != nil }

    public func insert(_ id: RequestID, at date: Date) {
        entries[hash(id)] = date.timeIntervalSince1970
        persist()
    }

    public func prune(olderThan date: Date) {
        let limit = date.timeIntervalSince1970
        let before = entries.count
        entries = entries.filter { $0.value >= limit }
        if entries.count != before { persist() }
    }

    private func persist() {
        store.set(try? JSONEncoder().encode(entries), forKey: Self.key)
    }
}
