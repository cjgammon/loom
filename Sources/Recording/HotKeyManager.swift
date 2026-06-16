import Foundation
import Carbon.HIToolbox

/// Registers a single system-wide hotkey via Carbon's `RegisterEventHotKey`, which —
/// unlike an `NSEvent` global monitor — fires even while Spool is frontmost and needs
/// no Accessibility permission. Used to start/stop recording from anywhere.
///
/// Default binding: ⌥⌘R.
final class HotKeyManager {
    /// Invoked on the main thread when the hotkey is pressed.
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register(keyCode: UInt32 = UInt32(kVK_ANSI_R),
                  modifiers: UInt32 = UInt32(cmdKey | optionKey)) {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.onTrigger?()
            return noErr
        }, 1, &spec, context, &handlerRef)

        let id = EventHotKeyID(signature: Self.fourCharCode("SPLR"), id: 1)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }

    deinit { unregister() }

    private static func fourCharCode(_ string: String) -> OSType {
        var result: OSType = 0
        for byte in string.utf8.prefix(4) { result = (result << 8) + OSType(byte) }
        return result
    }
}
