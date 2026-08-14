import Foundation

/// Small persisted preferences store. Deliberately minimal per spec
/// section 43 — no user accounts, no sync, just UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let homepage = "settings.homepage"
        static let startInFullScreen = "settings.startInFullScreen"
        static let autoActivateBrowser = "settings.autoActivateBrowser"
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

    private init() {
        homepage = UserDefaults.standard.string(forKey: Keys.homepage) ?? "about:blank"
        startInFullScreen = UserDefaults.standard.bool(forKey: Keys.startInFullScreen)
        autoActivateBrowser = UserDefaults.standard.bool(forKey: Keys.autoActivateBrowser)
    }
}
