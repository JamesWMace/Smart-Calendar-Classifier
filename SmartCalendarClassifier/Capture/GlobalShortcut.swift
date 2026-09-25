import AppKit
import Carbon.HIToolbox

/// The system-wide shortcut that captures the selection.
struct GlobalShortcut: Codable, Equatable {
    var keyCode: Int
    /// Carbon flags (`cmdKey`, `optionKey`, …) as `RegisterEventHotKey` wants them.
    var carbonModifiers: Int
    /// The key's character, lowercased, for menu key equivalents ("" for special keys).
    var key: String
    /// e.g. "⌃⌥C"
    var display: String

    static let standard = GlobalShortcut(keyCode: kVK_ANSI_C, carbonModifiers: controlKey | optionKey, key: "c", display: "⌃⌥C")

    /// From a key press in the recorder; nil unless it includes ⌘, ⌃ or ⌥ (a bare key or
    /// ⇧-key would fire while typing).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard !flags.subtracting(.shift).isEmpty else { return nil }
        let keyCode = Int(event.keyCode)
        let name = Self.specialKeys[keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "?"
        self.keyCode = keyCode
        carbonModifiers = (flags.contains(.control) ? controlKey : 0) | (flags.contains(.option) ? optionKey : 0)
            | (flags.contains(.shift) ? shiftKey : 0) | (flags.contains(.command) ? cmdKey : 0)
        key = Self.specialKeys[keyCode] == nil ? (event.charactersIgnoringModifiers?.lowercased() ?? "") : ""
        display = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
            + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "") + name
    }

    init(keyCode: Int, carbonModifiers: Int, key: String, display: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.key = key
        self.display = display
    }

    var menuModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & controlKey != 0 { flags.insert(.control) }
        if carbonModifiers & optionKey != 0 { flags.insert(.option) }
        if carbonModifiers & shiftKey != 0 { flags.insert(.shift) }
        if carbonModifiers & cmdKey != 0 { flags.insert(.command) }
        return flags
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

/// The current shortcut, persisted, plus whether it could be registered.
@MainActor
@Observable
final class ShortcutStore {
    static let shared = ShortcutStore()
    private static let defaultsKey = "globalShortcut"

    var shortcut: GlobalShortcut {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(shortcut), forKey: Self.defaultsKey)
            onChange?()
        }
    }

    /// While the recorder listens, the hotkey is released so pressing it records instead.
    var isRecording = false {
        didSet { onChange?() }
    }

    /// Set when another app already owns the combination.
    var registrationError: String?

    /// Re-registers the hotkey; set by the app delegate.
    @ObservationIgnored var onChange: (() -> Void)?

    private init() {
        shortcut = UserDefaults.standard.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(GlobalShortcut.self, from: $0) } ?? .standard
    }
}
