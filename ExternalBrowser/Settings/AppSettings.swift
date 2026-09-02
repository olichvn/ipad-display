import Foundation

/// Small persisted preferences store. Deliberately minimal per spec
/// section 43 — no user accounts, no sync, just UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Posted when pointerLockEnabled changes, so the hosting controller
    /// can ask UIKit to re-evaluate its pointer lock preference.
    static let pointerLockPreferenceChanged = Notification.Name("pointerLockPreferenceChanged")

    private enum Keys {
        static let homepage = "settings.homepage"
        static let startInFullScreen = "settings.startInFullScreen"
        static let autoActivateBrowser = "settings.autoActivateBrowser"
        static let pointerLock = "settings.pointerLock"
        static let pcKeyboard = "settings.pcKeyboard"
    }

    @Published var homepage: String {
        didSet { UserDefaults.standard.set(homepage, forKey: Keys.homepage) }
    }
    @Published var startInFullScreen: Bool {
        didSet { UserDefaults.standard.set(startInFullScreen, forKey: Keys.startInFullScreen) }
    }
    @Published var autoActivateBrowser: Bool {
        didSet { UserDefaults.standard.set(autoActivateBrowser, forKey: Keys.autoActivateBrowser) }
    }

    /// Captures the mouse so it stops driving the iPad's own system
    /// pointer. Exposed as a toggle because pointer lock has proven
    /// fragile on this hardware — if it misbehaves, turning it off
    /// restores basic (edge-limited) mouse control without a rebuild.
    /// Which physical key should produce Alt.
    ///
    /// iPadOS remaps modifiers on non-Apple keyboards so the key beside
    /// the spacebar behaves as Command — which on a PC keyboard is Alt.
    /// Rather than guessing the keyboard, this states the mapping
    /// outright. `.both` is the default because it cannot be wrong: Alt
    /// reaches a remote session whichever key iPadOS decided to deliver.
    /// The cost is that Command/Super is then unavailable remotely.
    enum AltKeySource: String, CaseIterable, Identifiable {
        case option    // Apple layout: the Option key sends Alt
        case command   // PC layout: the key beside the spacebar sends Alt
        case both      // either key sends Alt

        var id: String { rawValue }

        var label: String {
            switch self {
            case .option: return "Option only"
            case .command: return "Command only"
            case .both: return "Option or Command"
            }
        }
    }

    @Published var altKeySource: AltKeySource {
        didSet { UserDefaults.standard.set(altKeySource.rawValue, forKey: Keys.pcKeyboard) }
    }

    @Published var pointerLockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(pointerLockEnabled, forKey: Keys.pointerLock)
            NotificationCenter.default.post(name: AppSettings.pointerLockPreferenceChanged, object: nil)
        }
    }

    private init() {
        homepage = UserDefaults.standard.string(forKey: Keys.homepage) ?? "about:blank"
        startInFullScreen = UserDefaults.standard.bool(forKey: Keys.startInFullScreen)
        autoActivateBrowser = UserDefaults.standard.bool(forKey: Keys.autoActivateBrowser)
        // Defaults to on (bool(forKey:) would give false for an unset key).
        pointerLockEnabled = UserDefaults.standard.object(forKey: Keys.pointerLock) as? Bool ?? true
        altKeySource = AltKeySource(rawValue: UserDefaults.standard.string(forKey: Keys.pcKeyboard) ?? "") ?? .both
    }
}
