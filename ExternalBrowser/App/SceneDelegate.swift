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
        window.rootViewController = PointerLockingHostingController(rootView: controller)
        self.window = window
        window.makeKeyAndVisible()
    }
}

/// Without this, the mouse still drives the iPad's own (unused) system
/// pointer, which the OS confines to the iPad's screen bounds — so raw
/// GCMouse deltas stop being generated the moment that hidden pointer
/// hits an edge, well before the tracked cursor on the external display
/// reaches the edge of ITS screen. Pointer lock (the same mechanism
/// full-screen games use for mouse-look) hides the system pointer
/// entirely and reports unbounded relative motion instead, which is
/// what InputRelay actually needs.
final class PointerLockingHostingController<Content: View>: UIHostingController<Content> {
    override var prefersPointerLocked: Bool { true }

    // Presenting anything on top (e.g. the Settings sheet) makes UIKit
    // drop pointer lock, since the presented content doesn't request it.
    // It isn't automatically re-requested on dismiss, so the mouse would
    // stay stuck driving the (unused) system pointer forever after the
    // first time Settings was opened. Re-assert on every reappearance.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsUpdateOfPrefersPointerLocked()
    }
}
