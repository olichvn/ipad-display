import UIKit
import SwiftUI

/// The external monitor's own scene, connected by the system when a
/// USB-C/DisplayPort display is attached and the app declares support
/// for the `.windowExternalDisplayNonInteractive` scene role in
/// Info.plist. This is a genuinely separate UIWindowScene from the
/// iPad's own — not a mirror — which is what actually stops the OS from
/// falling back to plain screen mirroring.
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

        ExternalDisplayManager.shared.sceneConnected(window: window, screen: windowScene.screen)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        ExternalDisplayManager.shared.sceneDisconnected()
        window = nil
    }

    /// Fires on resolution/mode changes so the published geometry (shown
    /// on the iPad controller) stays accurate.
    func windowScene(_ windowScene: UIWindowScene, didUpdateCoordinateSpace previousCoordinateSpace: UICoordinateSpace, interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation, traitCollection previousTraitCollection: UITraitCollection) {
        ExternalDisplayManager.shared.updateGeometry(for: windowScene.screen)
    }
}
