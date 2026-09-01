import UIKit
import SwiftUI

/// The external monitor's own scene. Genuinely fills the display at its
/// own native resolution (unlike plain OS mirroring, which letterboxes
/// to the iPad's own aspect ratio) — but per Apple's design, this scene
/// role accepts no touch/mouse/keyboard input at all. Real interaction
/// is supplied separately by InputRelay, which reads raw mouse/keyboard
/// via the GameController framework and forwards it into the page as
/// synthetic DOM events, bypassing the normal window-focus routing this
/// role blocks.
class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(
            rootView: BrowserView().environmentObject(BrowserEngine.shared)
        )
        self.window = window
        window.isHidden = false

        ExternalDisplayManager.shared.sceneConnected(screen: windowScene.screen)
        InputRelay.shared.attach(to: BrowserEngine.shared.webView, toolbar: BrowserEngine.shared.toolbarWebView)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        ExternalDisplayManager.shared.sceneDisconnected()
        InputRelay.shared.detach()
        window = nil
    }

    func windowScene(_ windowScene: UIWindowScene, didUpdate previousCoordinateSpace: UICoordinateSpace, interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation, traitCollection previousTraitCollection: UITraitCollection) {
        ExternalDisplayManager.shared.updateGeometry(for: windowScene.screen)
    }
}
