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

        // Always load the homepage, rather than only when "automatically
        // activate browser" is set: the page needs a live document as
        // soon as the display is connected, both so there's something to
        // look at and because the input relay dispatches into that
        // document's JavaScript context.
        BrowserEngine.shared.ensureDocumentLoaded()

        if AppSettings.shared.startInFullScreen {
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
