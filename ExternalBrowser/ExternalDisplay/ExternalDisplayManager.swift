import UIKit
import Combine

/// Published status about the external display scene, for the iPad
/// controller's status panel. The scene/window lifecycle itself is
/// owned by ExternalDisplaySceneDelegate; this is purely a status
/// mirror plus the trigger point for starting/stopping InputRelay.
final class ExternalDisplayManager: ObservableObject {
    static let shared = ExternalDisplayManager()

    /// Posted when the external display connects or disconnects, so UIKit
    /// code (which can't observe @Published) can react.
    static let connectionChanged = Notification.Name("externalDisplayConnectionChanged")

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var displayName: String = ""
    @Published private(set) var pixelResolution: CGSize = .zero
    @Published private(set) var pointSize: CGSize = .zero

    private init() {}

    func sceneConnected(screen: UIScreen) {
        updateGeometry(for: screen)
        displayName = "External Display"
        isConnected = true

        // Always load something, rather than only when "automatically
        // activate browser" is set: the input relay drives the page by
        // injecting into its JavaScript context, and with no document
        // loaded there is nothing to inject into — which made the mouse
        // look dead until a URL was entered by hand.
        BrowserEngine.shared.ensureDocumentLoaded()

        if AppSettings.shared.startInFullScreen {
            BrowserEngine.shared.setFullScreen(true)
        }
        NotificationCenter.default.post(name: ExternalDisplayManager.connectionChanged, object: nil)
    }

    func sceneDisconnected() {
        isConnected = false
        displayName = ""
        pixelResolution = .zero
        pointSize = .zero
        NotificationCenter.default.post(name: ExternalDisplayManager.connectionChanged, object: nil)
    }

    func updateGeometry(for screen: UIScreen) {
        pixelResolution = screen.currentMode?.size ?? screen.bounds.size
        pointSize = screen.bounds.size
    }
}
