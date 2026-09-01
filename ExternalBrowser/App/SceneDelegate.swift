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

/// Captures the mouse so it stops driving the iPad's own system pointer.
/// Without this the OS clamps that pointer to the iPad's screen and
/// simply stops delivering GCMouse deltas once it hits an edge, so the
/// tracked cursor on the external display gets stuck partway across —
/// and stray clicks land on the iPad's own UI.
///
/// The critical piece is `childViewControllerForPointerLock`: UIKit asks
/// the root view controller, but by default defers to a child if there
/// is one. SwiftUI's NavigationView/Form build child controllers that
/// don't request pointer lock, so an earlier version of this returned
/// the wrong answer and lock never properly engaged — it disturbed the
/// system pointer without capturing it. Returning nil keeps the decision
/// here.
final class PointerLockingHostingController<Content: View>: UIHostingController<Content> {
    override var prefersPointerLocked: Bool {
        AppSettings.shared.pointerLockEnabled
    }

    override var childViewControllerForPointerLock: UIViewController? { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pointerLockPreferenceChanged),
            name: AppSettings.pointerLockPreferenceChanged,
            object: nil
        )
    }

    @objc private func pointerLockPreferenceChanged() {
        setNeedsUpdateOfPrefersPointerLocked()
    }
}
