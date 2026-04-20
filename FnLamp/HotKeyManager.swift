// HotKeyManager.swift
// Registers and manages a system-wide hotkey using the Carbon Event Manager.
// Because Carbon callbacks are C functions, the handler and hotkey ref are stored
// in file-scope globals rather than instance properties.

import Carbon
import AppKit

// MARK: - C-callback-compatible globals (Carbon interop)

nonisolated(unsafe) private var _hotKeyRef: EventHotKeyRef?
nonisolated(unsafe) private var _hotKeyEventHandlerRef: EventHandlerRef?
nonisolated(unsafe) private var _hotKeyAction: (() -> Void)?

// MARK: - HotKeyManager

@MainActor
final class HotKeyManager {

    // Default: Cmd+Ctrl+Option+F
    static let defaultKeyCode: Int = Int(kVK_ANSI_F)
    static let defaultModifiers: Int = Int(cmdKey) | Int(controlKey) | Int(optionKey)

    private static let keyCodeUD  = "fnlamp.hotkeyCode"
    private static let modifiersUD = "fnlamp.hotkeyModifiers"

    var keyCode: Int {
        get { UserDefaults.standard.object(forKey: Self.keyCodeUD) as? Int ?? Self.defaultKeyCode }
        set { UserDefaults.standard.set(newValue, forKey: Self.keyCodeUD) }
    }

    var modifiers: Int {
        get { UserDefaults.standard.object(forKey: Self.modifiersUD) as? Int ?? Self.defaultModifiers }
        set { UserDefaults.standard.set(newValue, forKey: Self.modifiersUD) }
    }

    init(onTrigger: @escaping @MainActor () -> Void) {
        _hotKeyAction = { Task { @MainActor in onTrigger() } }
        installCarbonEventHandler()
    }

    // Registers the current keyCode/modifiers combination as a system-wide hotkey.
    // Unregisters any previously registered hotkey first to avoid duplicates.
    // Returns true if registration succeeded.
    @discardableResult
    func register() -> Bool {
        unregister()
        let id = EventHotKeyID(signature: 0x464E_4C50, id: 1) // 'FNLP'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers),
                                         id, GetApplicationEventTarget(), 0, &_hotKeyRef)
        return status == noErr
    }

    // Unregisters the active hotkey reference and clears the stored ref.
    func unregister() {
        guard let ref = _hotKeyRef else { return }
        UnregisterEventHotKey(ref)
        _hotKeyRef = nil
    }

    // Saves and re-registers the hotkey with new keyCode/modifiers.
    // Returns false and rolls back to the previous values if the new shortcut is already taken by another app.
    @discardableResult
    func update(keyCode: Int, modifiers: Int) -> Bool {
        let prevKeyCode  = self.keyCode
        let prevModifiers = self.modifiers
        unregister()
        self.keyCode = keyCode
        self.modifiers = modifiers
        if register() { return true }
        // Rollback on failure
        self.keyCode = prevKeyCode
        self.modifiers = prevModifiers
        register()
        return false
    }

    // MARK: - Private

    // Installs a Carbon event handler that fires _hotKeyAction on every hotkey press.
    // Guards against double installation since the handler ref is a global singleton.
    private func installCarbonEventHandler() {
        guard _hotKeyEventHandlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                DispatchQueue.main.async { _hotKeyAction?() }
                return noErr
            },
            1, &spec, nil, &_hotKeyEventHandlerRef
        )
    }
}

// MARK: - Helpers

// Converts NSEvent modifier flags to the Carbon modifier bitmask format
// expected by RegisterEventHotKey.
func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
    var result = 0
    if flags.contains(.control) { result |= Int(controlKey) }
    if flags.contains(.option)  { result |= Int(optionKey) }
    if flags.contains(.shift)   { result |= Int(shiftKey) }
    if flags.contains(.command) { result |= Int(cmdKey) }
    return result
}

// Builds a human-readable shortcut string (e.g. "⌃⌥⌘F") from Carbon key code and modifier values.
func shortcutDisplayString(keyCode: Int, modifiers: Int) -> String {
    var s = ""
    if modifiers & Int(controlKey) != 0 { s += "⌃" }
    if modifiers & Int(optionKey)  != 0 { s += "⌥" }
    if modifiers & Int(shiftKey)   != 0 { s += "⇧" }
    if modifiers & Int(cmdKey)     != 0 { s += "⌘" }
    s += keyDisplayName(for: keyCode)
    return s
}

// Maps a Carbon key code to its display label (e.g. kVK_ANSI_F → "F").
// Returns "?" for unmapped codes.
func keyDisplayName(for keyCode: Int) -> String {
    let table: [Int: String] = [
        Int(kVK_ANSI_A): "A", Int(kVK_ANSI_B): "B", Int(kVK_ANSI_C): "C",
        Int(kVK_ANSI_D): "D", Int(kVK_ANSI_E): "E", Int(kVK_ANSI_F): "F",
        Int(kVK_ANSI_G): "G", Int(kVK_ANSI_H): "H", Int(kVK_ANSI_I): "I",
        Int(kVK_ANSI_J): "J", Int(kVK_ANSI_K): "K", Int(kVK_ANSI_L): "L",
        Int(kVK_ANSI_M): "M", Int(kVK_ANSI_N): "N", Int(kVK_ANSI_O): "O",
        Int(kVK_ANSI_P): "P", Int(kVK_ANSI_Q): "Q", Int(kVK_ANSI_R): "R",
        Int(kVK_ANSI_S): "S", Int(kVK_ANSI_T): "T", Int(kVK_ANSI_U): "U",
        Int(kVK_ANSI_V): "V", Int(kVK_ANSI_W): "W", Int(kVK_ANSI_X): "X",
        Int(kVK_ANSI_Y): "Y", Int(kVK_ANSI_Z): "Z",
        Int(kVK_ANSI_0): "0", Int(kVK_ANSI_1): "1", Int(kVK_ANSI_2): "2",
        Int(kVK_ANSI_3): "3", Int(kVK_ANSI_4): "4", Int(kVK_ANSI_5): "5",
        Int(kVK_ANSI_6): "6", Int(kVK_ANSI_7): "7", Int(kVK_ANSI_8): "8",
        Int(kVK_ANSI_9): "9",
        Int(kVK_ANSI_Minus): "-",   Int(kVK_ANSI_Equal): "=",
        Int(kVK_ANSI_LeftBracket): "[", Int(kVK_ANSI_RightBracket): "]",
        Int(kVK_ANSI_Backslash): "\\", Int(kVK_ANSI_Semicolon): ";",
        Int(kVK_ANSI_Quote): "'",   Int(kVK_ANSI_Grave): "`",
        Int(kVK_ANSI_Comma): ",",   Int(kVK_ANSI_Period): ".",
        Int(kVK_ANSI_Slash): "/",
        Int(kVK_Return): "↩",    Int(kVK_Tab): "⇥",
        Int(kVK_Space): "Space", Int(kVK_Delete): "⌫",
        Int(kVK_Escape): "⎋",
        Int(kVK_F1): "F1",   Int(kVK_F2): "F2",   Int(kVK_F3): "F3",
        Int(kVK_F4): "F4",   Int(kVK_F5): "F5",   Int(kVK_F6): "F6",
        Int(kVK_F7): "F7",   Int(kVK_F8): "F8",   Int(kVK_F9): "F9",
        Int(kVK_F10): "F10", Int(kVK_F11): "F11", Int(kVK_F12): "F12",
    ]
    return table[keyCode] ?? "?"
}
