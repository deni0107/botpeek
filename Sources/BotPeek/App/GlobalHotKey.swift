#if canImport(AppKit)
import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut. Uses Carbon's hot key API, which needs
/// no Accessibility or Input Monitoring permission and sees only this one
/// key combination, never other typing.
@MainActor
final class GlobalHotKey {
    /// Control-Option-B, shown to the user as "⌃⌥B".
    static let display = "⌃⌥B"
    private static let keyCode = UInt32(kVK_ANSI_B)
    private static let modifiers = UInt32(controlKey | optionKey)
    private static let signature: OSType = 0x4250_4B31 // "BPK1"

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    var isRegistered: Bool { hotKey != nil }

    /// Returns false when another app already owns the combination.
    @discardableResult
    func register() -> Bool {
        guard hotKey == nil else { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, context, &handler)
        guard installed == noErr else { return false }

        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(Self.keyCode, Self.modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr {
            hotKey = nil
            unregister()
            return false
        }
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }
}
#endif
