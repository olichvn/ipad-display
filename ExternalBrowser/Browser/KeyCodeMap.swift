import GameController

/// Best-effort US-QWERTY mapping from raw GCKeyCode (HID usage codes)
/// to characters and DOM key names, for forwarding physical keyboard
/// input into the page as synthetic events. Non-US layouts and dead
/// keys are a known limitation — this covers the common case needed
/// to type URLs, login forms, and interact with a remote-desktop
/// session (e.g. Guacamole).
enum KeyCodeMap {
    struct Mapped {
        let domKey: String
        let char: Character?
    }

    static func map(_ keyCode: GCKeyCode, shift: Bool) -> Mapped? {
        if let letter = letters[keyCode] {
            let ch = shift ? Character(letter.uppercased()) : letter
            return Mapped(domKey: String(ch), char: ch)
        }
        if let digit = digits[keyCode] {
            let ch = shift ? digit.shifted : digit.plain
            return Mapped(domKey: String(ch), char: ch)
        }
        if let sym = symbols[keyCode] {
            let ch = shift ? sym.shifted : sym.plain
            return Mapped(domKey: String(ch), char: ch)
        }
        if keyCode == .spacebar {
            return Mapped(domKey: " ", char: " ")
        }
        if let named = namedKeys[keyCode] {
            return Mapped(domKey: named, char: nil)
        }
        return nil
    }

    private static let letters: [GCKeyCode: Character] = [
        .keyA: "a", .keyB: "b", .keyC: "c", .keyD: "d", .keyE: "e", .keyF: "f",
        .keyG: "g", .keyH: "h", .keyI: "i", .keyJ: "j", .keyK: "k", .keyL: "l",
        .keyM: "m", .keyN: "n", .keyO: "o", .keyP: "p", .keyQ: "q", .keyR: "r",
        .keyS: "s", .keyT: "t", .keyU: "u", .keyV: "v", .keyW: "w", .keyX: "x",
        .keyY: "y", .keyZ: "z"
    ]

    private static let digits: [GCKeyCode: (plain: Character, shifted: Character)] = [
        .one: ("1", "!"), .two: ("2", "@"), .three: ("3", "#"), .four: ("4", "$"),
        .five: ("5", "%"), .six: ("6", "^"), .seven: ("7", "&"), .eight: ("8", "*"),
        .nine: ("9", "("), .zero: ("0", ")")
    ]

    private static let symbols: [GCKeyCode: (plain: Character, shifted: Character)] = [
        .hyphen: ("-", "_"), .equalSign: ("=", "+"),
        .openBracket: ("[", "{"), .closeBracket: ("]", "}"),
        .backslash: ("\\", "|"), .semicolon: (";", ":"),
        .quote: ("'", "\""), .comma: (",", "<"),
        .period: (".", ">"), .slash: ("/", "?"),
        .graveAccentAndTilde: ("`", "~")
    ]

    private static let namedKeys: [GCKeyCode: String] = [
        .returnOrEnter: "Enter",
        .deleteOrBackspace: "Backspace",
        .tab: "Tab",
        .escape: "Escape",
        .upArrow: "ArrowUp",
        .downArrow: "ArrowDown",
        .leftArrow: "ArrowLeft",
        .rightArrow: "ArrowRight",
        .home: "Home",
        .end: "End",
        .pageUp: "PageUp",
        .pageDown: "PageDown",
        .deleteForward: "Delete"
    ]

    enum Modifier {
        case shift, control, alt, meta

        /// The DOM `KeyboardEvent.key` name when the modifier itself is
        /// forwarded as a keydown/keyup (not just a flag on other events).
        var domKey: String {
            switch self {
            case .shift: return "Shift"
            case .control: return "Control"
            case .alt: return "Alt"
            case .meta: return "Meta"
            }
        }
    }

    static func modifier(for keyCode: GCKeyCode) -> Modifier? {
        switch keyCode {
        case .leftShift, .rightShift: return .shift
        case .leftControl, .rightControl: return .control
        case .leftAlt, .rightAlt: return .alt
        case .leftGUI, .rightGUI: return .meta
        default: return nil
        }
    }
}
