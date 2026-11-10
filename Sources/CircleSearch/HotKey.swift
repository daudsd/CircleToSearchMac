import Carbon.HIToolbox
import Foundation

/// C callback for Carbon; hops to the main actor and fires the handler.
private func hotKeyEventHandler(
    _ call: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    DispatchQueue.main.async {
        MainActor.assumeIsolated { HotKeyManager.shared.onPress?() }
    }
    return noErr
}

/// Registers one system-wide shortcut using the Carbon hot key API
/// (works without Accessibility permission).
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onPress: (@MainActor () -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &spec,
            nil,
            &handlerRef
        )
    }

    /// Returns false if the shortcut is already taken by another app.
    @discardableResult
    func register(_ preset: HotKeyPreset) -> Bool {
        installHandlerIfNeeded()
        if let existing = hotKeyRef {
            UnregisterEventHotKey(existing)
            hotKeyRef = nil
        }
        let id = EventHotKeyID(signature: OSType(0x4353_4348), id: 1) // "CSCH"
        let status = RegisterEventHotKey(
            preset.keyCode,
            preset.modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        return status == noErr
    }
}
