import UIKit
import SwiftUI

/// The iPad's own on-screen scene. This always hosts the controller UI —
/// it never shows the web page itself, so the iPad and the external
/// monitor are never simply mirroring each other (see ControllerView).
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
