import Foundation

/// A shortcut in Carbon terms, the form `KeyboardShortcuts.Shortcut(carbonKeyCode:carbonModifiers:)` takes.
public struct KeyBinding: Hashable, Sendable {
    public let carbonKeyCode: Int
    public let carbonModifiers: Int

    public init(carbonKeyCode: Int, carbonModifiers: Int) {
        self.carbonKeyCode = carbonKeyCode
        self.carbonModifiers = carbonModifiers
    }

    /// Parses Spectacle's `shortcut_key_binding`, e.g. `alt+shift+cmd+z`.
    public init?(spectacle string: String) {
        let parts = string.lowercased().split(separator: "+").map(String.init)
        guard let keyName = parts.last, let code = Self.keyCodes[keyName] else { return nil }
        var modifiers = 0
        for name in parts.dropLast() {
            guard let flag = Self.modifierFlags[name] else { return nil }
            modifiers |= flag
        }
        self.init(carbonKeyCode: code, carbonModifiers: modifiers)
    }

    // Carbon `cmdKey`, `shiftKey`, `optionKey`, `controlKey` from HIToolbox Events.h.
    static let modifierFlags: [String: Int] = ["cmd": 256, "shift": 512, "alt": 2048, "ctrl": 4096]

    // Carbon `kVK_*` virtual key codes (ANSI layout) from HIToolbox Events.h.
    static let keyCodes: [String: Int] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
        "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50,
        "delete": 51, "escape": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]
}
