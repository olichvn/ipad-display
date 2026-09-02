import GameController

/// Best-effort US-QWERTY mapping from raw GCKeyCode (HID usage codes)
/// to the DOM identifiers a synthetic KeyboardEvent needs to carry:
/// `key` (the character/name), `code` (physical key, layout-independent,
/// e.g. "Digit1" not "1"), and the legacy numeric `keyCode`/`which`.
/// Many real-world consumers — Guacamole's keyboard handling included —
/// check `code`/`keyCode` as well as (or instead of) `key`, so leaving
/// them unset silently breaks combinations like Alt+1 even though plain
/// typing works fine. Non-US layouts and dead keys are a known
/// limitation.
enum KeyCodeMap {
    struct Mapped {
        let domKey: String
        let code: String
        let keyCode: Int
        let char: Character?
    }

    static func map(_ keyCode: GCKeyCode, shift: Bool) -> Mapped? {
        if let entry = letters[keyCode] {
            let ch = shift ? Character(entry.char.uppercased()) : entry.char
            return Mapped(domKey: String(ch), code: entry.code, keyCode: entry.keyCode, char: ch)
        }
        if let entry = digits[keyCode] {
            let ch = shift ? entry.shifted : entry.plain
            return Mapped(domKey: String(ch), code: entry.code, keyCode: entry.keyCode, char: ch)
        }
        if let entry = symbols[keyCode] {
            let ch = shift ? entry.shifted : entry.plain
            return Mapped(domKey: String(ch), code: entry.code, keyCode: entry.keyCode, char: ch)
        }
        if keyCode == .spacebar {
            return Mapped(domKey: " ", code: "Space", keyCode: 32, char: " ")
        }
        if let named = namedKeys[keyCode] {
            return Mapped(domKey: named.key, code: named.code, keyCode: named.keyCode, char: nil)
        }
        // Numeric keypad, always treated as numeric regardless of Num
        // Lock. The keypad's own DOM codes ("Numpad4" rather than
        // "Digit4") are deliberate: remote-desktop sessions distinguish
        // keypad keys from the number row.
        if let pad = keypad[keyCode] {
            return Mapped(domKey: pad.key, code: pad.code, keyCode: pad.keyCode, char: pad.char)
        }
        return nil
    }

    private static let letters: [GCKeyCode: (char: Character, code: String, keyCode: Int)] = [
        .keyA: ("a", "KeyA", 65), .keyB: ("b", "KeyB", 66), .keyC: ("c", "KeyC", 67),
        .keyD: ("d", "KeyD", 68), .keyE: ("e", "KeyE", 69), .keyF: ("f", "KeyF", 70),
        .keyG: ("g", "KeyG", 71), .keyH: ("h", "KeyH", 72), .keyI: ("i", "KeyI", 73),
        .keyJ: ("j", "KeyJ", 74), .keyK: ("k", "KeyK", 75), .keyL: ("l", "KeyL", 76),
        .keyM: ("m", "KeyM", 77), .keyN: ("n", "KeyN", 78), .keyO: ("o", "KeyO", 79),
        .keyP: ("p", "KeyP", 80), .keyQ: ("q", "KeyQ", 81), .keyR: ("r", "KeyR", 82),
        .keyS: ("s", "KeyS", 83), .keyT: ("t", "KeyT", 84), .keyU: ("u", "KeyU", 85),
        .keyV: ("v", "KeyV", 86), .keyW: ("w", "KeyW", 87), .keyX: ("x", "KeyX", 88),
        .keyY: ("y", "KeyY", 89), .keyZ: ("z", "KeyZ", 90)
    ]

    private static let digits: [GCKeyCode: (plain: Character, shifted: Character, code: String, keyCode: Int)] = [
        .one: ("1", "!", "Digit1", 49), .two: ("2", "@", "Digit2", 50),
        .three: ("3", "#", "Digit3", 51), .four: ("4", "$", "Digit4", 52),
        .five: ("5", "%", "Digit5", 53), .six: ("6", "^", "Digit6", 54),
        .seven: ("7", "&", "Digit7", 55), .eight: ("8", "*", "Digit8", 56),
        .nine: ("9", "(", "Digit9", 57), .zero: ("0", ")", "Digit0", 48)
    ]

    private static let keypad: [GCKeyCode: (key: String, code: String, keyCode: Int, char: Character?)] = [
        .keypad0: ("0", "Numpad0", 96, "0"),
        .keypad1: ("1", "Numpad1", 97, "1"),
        .keypad2: ("2", "Numpad2", 98, "2"),
        .keypad3: ("3", "Numpad3", 99, "3"),
        .keypad4: ("4", "Numpad4", 100, "4"),
        .keypad5: ("5", "Numpad5", 101, "5"),
        .keypad6: ("6", "Numpad6", 102, "6"),
        .keypad7: ("7", "Numpad7", 103, "7"),
        .keypad8: ("8", "Numpad8", 104, "8"),
        .keypad9: ("9", "Numpad9", 105, "9"),
        .keypadAsterisk: ("*", "NumpadMultiply", 106, "*"),
        .keypadPlus: ("+", "NumpadAdd", 107, "+"),
        .keypadHyphen: ("-", "NumpadSubtract", 109, "-"),
        .keypadPeriod: (".", "NumpadDecimal", 110, "."),
        .keypadSlash: ("/", "NumpadDivide", 111, "/"),
        .keypadEnter: ("Enter", "NumpadEnter", 13, nil)
    ]

    private static let symbols: [GCKeyCode: (plain: Character, shifted: Character, code: String, keyCode: Int)] = [
        .hyphen: ("-", "_", "Minus", 189), .equalSign: ("=", "+", "Equal", 187),
        .openBracket: ("[", "{", "BracketLeft", 219), .closeBracket: ("]", "}", "BracketRight", 221),
        .backslash: ("\\", "|", "Backslash", 220), .semicolon: (";", ":", "Semicolon", 186),
        .quote: ("'", "\"", "Quote", 222), .comma: (",", "<", "Comma", 188),
        .period: (".", ">", "Period", 190), .slash: ("/", "?", "Slash", 191),
        .graveAccentAndTilde: ("`", "~", "Backquote", 192)
    ]

    private static let namedKeys: [GCKeyCode: (key: String, code: String, keyCode: Int)] = [
        .returnOrEnter: ("Enter", "Enter", 13),
        .deleteOrBackspace: ("Backspace", "Backspace", 8),
        .tab: ("Tab", "Tab", 9),
        .escape: ("Escape", "Escape", 27),
        .upArrow: ("ArrowUp", "ArrowUp", 38),
        .downArrow: ("ArrowDown", "ArrowDown", 40),
        .leftArrow: ("ArrowLeft", "ArrowLeft", 37),
        .rightArrow: ("ArrowRight", "ArrowRight", 39),
        .home: ("Home", "Home", 36),
        .end: ("End", "End", 35),
        .pageUp: ("PageUp", "PageUp", 33),
        .pageDown: ("PageDown", "PageDown", 34),
        .deleteForward: ("Delete", "Delete", 46),
        .capsLock: ("CapsLock", "CapsLock", 20)
        // F1-F12 omitted: GCKeyCode has no .f1...f12 members (confirmed
        // by a failed build) - not essential for the current use case.
    ]

    enum ModifierKind {
        case shift, control, alt, meta
    }

    struct Modifier {
        let kind: ModifierKind
        let domKey: String
        let code: String
        let keyCode: Int
    }

    /// Exchanges Command and Alt.
    ///
    /// iPadOS remaps modifiers on non-Apple keyboards so the key beside
    /// the spacebar acts as Command — which on a PC keyboard is the Alt
    /// key. The result is that pressing Alt sends Command and a remote
    /// session never sees Alt at all. Since raw HID is read here, the
    /// mapping can simply be undone.
    static func swappingCommandAndAlt(_ modifier: Modifier) -> Modifier {
        let isRight = modifier.code.hasSuffix("Right")
        switch modifier.kind {
        case .meta:
            return Modifier(kind: .alt, domKey: "Alt",
                            code: isRight ? "AltRight" : "AltLeft", keyCode: 18)
        case .alt:
            return Modifier(kind: .meta, domKey: "Meta",
                            code: isRight ? "MetaRight" : "MetaLeft", keyCode: isRight ? 93 : 91)
        case .shift, .control:
            return modifier
        }
    }

    static func modifier(for keyCode: GCKeyCode) -> Modifier? {
        switch keyCode {
        case .leftShift: return Modifier(kind: .shift, domKey: "Shift", code: "ShiftLeft", keyCode: 16)
        case .rightShift: return Modifier(kind: .shift, domKey: "Shift", code: "ShiftRight", keyCode: 16)
        case .leftControl: return Modifier(kind: .control, domKey: "Control", code: "ControlLeft", keyCode: 17)
        case .rightControl: return Modifier(kind: .control, domKey: "Control", code: "ControlRight", keyCode: 17)
        case .leftAlt: return Modifier(kind: .alt, domKey: "Alt", code: "AltLeft", keyCode: 18)
        case .rightAlt: return Modifier(kind: .alt, domKey: "Alt", code: "AltRight", keyCode: 18)
        case .leftGUI: return Modifier(kind: .meta, domKey: "Meta", code: "MetaLeft", keyCode: 91)
        case .rightGUI: return Modifier(kind: .meta, domKey: "Meta", code: "MetaRight", keyCode: 93)
        default: return nil
        }
    }
}
