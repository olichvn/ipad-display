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
