import UIKit
import Combine

/// Published status about the external display scene, for the iPad
/// controller's status panel. The scene/window lifecycle itself is
/// owned by ExternalDisplaySceneDelegate; this is purely a status
/// mirror plus the trigger point for starting/stopping InputRelay.
final class ExternalDisplayManager: ObservableObject {
    static let shared = ExternalDisplayManager()

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var displayName: String = ""
    @Published private(set) var pixelResolution: CGSize = .zero
    @Published private(set) var pointSize: CGSize = .zero

    private init() {}

    func sceneConnected(screen: UIScreen) {
        updateGeometry(for: screen)
        displayName = "External Display"
        isConnected = true

        // Pointer lock is decided when the iPad's own scene appears —
        // before this display exists — and UIKit doesn't reconsider it on
        // its own. From a cold start that left the mouse driving the iPad
        // instead of the page, and manually toggling Capture Mouse off and
        // on was the only thing that fixed it: that toggle's sole effect
        // is forcing this re-evaluation. Do it automatically instead, once
        // the scene has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(name: AppSettings.pointerLockPreferenceChanged, object: nil)
        }

        let settings = AppSettings.shared
        if BrowserEngine.shared.state.url == nil, settings.autoActivateBrowser {
            BrowserEngine.shared.load(urlString: settings.homepage)
        }
        if settings.startInFullScreen {
            BrowserEngine.shared.setFullScreen(true)
        }
    }

    func sceneDisconnected() {
        isConnected = false
        displayName = ""
        pixelResolution = .zero
        pointSize = .zero
    }

    func updateGeometry(for screen: UIScreen) {
        pixelResolution = screen.currentMode?.size ?? screen.bounds.size
        pointSize = screen.bounds.size
    }
}
