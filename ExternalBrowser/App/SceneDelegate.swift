import UIKit
import SwiftUI

/// The iPad's own on-screen scene: controls and status only.
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let controller = ControllerView()
            .environmentObject(BrowserEngine.shared)
            .environmentObject(ExternalDisplayManager.shared)

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: controller)
        self.window = window
        window.makeKeyAndVisible()
    }
}

// Pointer lock (`prefersPointerLocked`) was tried here to stop the mouse
// from also driving the iPad's own system pointer. It never engaged
// reliably — Apple requires the scene to be full screen AND
// foregroundActive, and with an external display attached plus a
// sheet-capable SwiftUI hierarchy it ended up half-engaged: enough to
// disturb the system pointer (status bar flashing dark on click, the
// external-display indicator vanishing) but not enough to capture it,
// which broke mouse input entirely on hardware.
//
// InputRelay instead scales raw GCMouse deltas by the ratio between the
// external display and the iPad's own screen, so traversing the iPad's
// screen traverses the whole external display and the tracked cursor
// still reaches every edge. Trade-off: the iPad's own pointer stays
// visible on the iPad screen.
