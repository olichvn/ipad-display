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

    /// While the mouse is captured, the physical keyboard belongs to the
    /// page on the external display — InputRelay delivers it there via
    /// the GameController framework, which is a separate input path from
    /// the responder chain. Without swallowing these, every keystroke is
    /// ALSO handled by this scene's SwiftUI controls: Tab walks focus to
    /// the "Go" button and Enter presses it, and typed characters append
    /// to the iPad's own address field, so a later Enter navigates to a
    /// mangled URL.
    private var swallowsHardwareKeys: Bool {
        AppSettings.shared.pointerLockEnabled && ExternalDisplayManager.shared.isConnected
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if handleAppShortcut(presses) { return }
        guard !swallowsHardwareKeys else { return }
        super.pressesBegan(presses, with: event)
    }

    /// A couple of shortcuts survive the swallow above, so the browser can
    /// be driven entirely from the external keyboard without reaching for
    /// the iPad. Deliberately Command+Shift combinations: a remote Linux
    /// session uses Control/Alt, so these are unlikely to collide with
    /// anything being typed into it.
    private func handleAppShortcut(_ presses: Set<UIPress>) -> Bool {
        for press in presses {
            guard let key = press.key else { continue }
            let mods = key.modifierFlags
            guard mods.contains(.command), mods.contains(.shift) else { continue }
            switch key.charactersIgnoringModifiers.lowercased() {
            case "f":
                BrowserEngine.shared.toggleFullScreen()
                return true
            case "m":
                AppSettings.shared.pointerLockEnabled.toggle()
                return true
            default:
                continue
            }
        }
        return false
    }

    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard !swallowsHardwareKeys else { return }
        super.pressesChanged(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard !swallowsHardwareKeys else { return }
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard !swallowsHardwareKeys else { return }
        super.pressesCancelled(presses, with: event)
    }
}
