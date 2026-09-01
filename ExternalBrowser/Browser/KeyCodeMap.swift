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
        .capsLock: ("CapsLock", "CapsLock", 20),
        .f1: ("F1", "F1", 112), .f2: ("F2", "F2", 113), .f3: ("F3", "F3", 114),
        .f4: ("F4", "F4", 115), .f5: ("F5", "F5", 116), .f6: ("F6", "F6", 117),
        .f7: ("F7", "F7", 118), .f8: ("F8", "F8", 119), .f9: ("F9", "F9", 120),
        .f10: ("F10", "F10", 121), .f11: ("F11", "F11", 122), .f12: ("F12", "F12", 123)
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
