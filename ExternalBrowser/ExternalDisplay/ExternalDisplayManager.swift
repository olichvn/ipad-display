import UIKit
import Combine

/// Published status about the external display, plus a weak reference to
/// its UIWindow (owned by ExternalDisplaySceneDelegate, not here) so other
/// code — e.g. presenting a JS alert on the right screen — can find it.
///
/// The window itself is created/destroyed by ExternalDisplaySceneDelegate
/// in response to genuine UIWindowScene connect/disconnect lifecycle
/// events for the `.windowExternalDisplayNonInteractive` role. An earlier
/// version of this file drove a plain UIScreen + UIWindow(frame:) instead
/// (no scene role at all) — on real hardware that fell back to the OS's
/// automatic screen mirroring instead of giving the app its own external
/// window, which is exactly the failure mode the scene-role API exists
/// to avoid.
final class ExternalDisplayManager: ObservableObject {
    static let shared = ExternalDisplayManager()

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var displayName: String = ""
    /// Native pixel resolution of the external display (e.g. 3840x2160).
    @Published private(set) var pixelResolution: CGSize = .zero
    /// Point size of the external display's UIScreen bounds, i.e. the
    /// coordinate space the external UIWindow actually lays out in.
    @Published private(set) var pointSize: CGSize = .zero

    private(set) weak var externalWindow: UIWindow?

    private init() {}

    func sceneConnected(window: UIWindow, screen: UIScreen) {
        externalWindow = window
        updateGeometry(for: screen)
        displayName = "External Display"
        isConnected = true

        let settings = AppSettings.shared
        if BrowserEngine.shared.state.url == nil, settings.autoActivateBrowser {
            BrowserEngine.shared.load(urlString: settings.homepage)
        }
        if settings.startInFullScreen {
            BrowserEngine.shared.setFullScreen(true)
        }
    }

    func sceneDisconnected() {
        externalWindow = nil
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
