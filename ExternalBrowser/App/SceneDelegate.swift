import UIKit
import SwiftUI

/// The iPad's own on-screen scene: controls and status only.
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = SceneDelegate.makeRootController()
        self.window = window
        window.makeKeyAndVisible()

        // Rebuild the root controller when the external display appears.
        // A freshly installed root has its preferences read from scratch,
        // which is the most promising way found so far to make UIKit
        // re-read prefersPointerLocked without the user having to pull
        // Control Center down and back up.
        NotificationCenter.default.addObserver(
            self, selector: #selector(externalDisplayConnectionChanged),
            name: ExternalDisplayManager.connectionChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(swapRootController),
            name: PointerLockDiagnostics.requestRootSwap, object: nil)
    }

    @objc private func swapRootController() {
        guard let window = window else { return }
        PointerLockDiagnostics.shared.recordRearm("root swap (manual)")
        window.rootViewController = SceneDelegate.makeRootController()
    }

    static func makeRootController() -> UIViewController {
        let controller = ControllerView()
            .environmentObject(BrowserEngine.shared)
            .environmentObject(ExternalDisplayManager.shared)
        return PointerLockingHostingController(rootView: controller)
    }

    @objc private func externalDisplayConnectionChanged() {
        guard ExternalDisplayManager.shared.isConnected else { return }
        // Slight delay so the external scene has finished settling first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let window = self?.window else { return }
            PointerLockDiagnostics.shared.recordRearm("root swap")
            window.rootViewController = SceneDelegate.makeRootController()
        }
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
        // Counted so the iPad UI can show whether UIKit is actually
        // consulting us. A Control Center pull-down engages lock while
        // setNeedsUpdateOfPrefersPointerLocked() appears to do nothing,
        // and those are two very different problems: UIKit never asking
        // us, versus UIKit asking and the system refusing. The counter
        // tells them apart.
        PointerLockDiagnostics.shared.recordRead(AppSettings.shared.pointerLockEnabled)
        return AppSettings.shared.pointerLockEnabled
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
        // Re-arm on every genuine activation transition. UIKit re-reads
        // the preference itself at these moments, which is why pulling
        // Control Center down and up works; asking here as well means a
        // natural transition no longer needs the Capture Mouse toggle
        // first.
        NotificationCenter.default.addObserver(
            self, selector: #selector(rearmPointerLock),
            name: UIScene.didActivateNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(rearmPointerLock),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleGeometryNudgeRequest),
            name: PointerLockDiagnostics.requestGeometryNudge, object: nil)
    }

    @objc private func handleGeometryNudgeRequest() {
        nudgeSceneGeometry()
    }

    @objc private func pointerLockPreferenceChanged() {
        setNeedsUpdateOfPrefersPointerLocked()
    }

    @objc private func rearmPointerLock() {
        PointerLockDiagnostics.shared.recordRearm("activation")
        setNeedsUpdateOfPrefersPointerLocked()
    }

    /// Third lever: nudge the scene's geometry. Pointer lock is only
    /// granted to a full-screen scene, so making the system re-evaluate
    /// geometry may make it re-evaluate the lock along with it. The most
    /// speculative of the three attempts, hence its own entry point so it
    /// can be tried on its own.
    func nudgeSceneGeometry() {
        guard let windowScene = view.window?.windowScene else { return }
        PointerLockDiagnostics.shared.recordRearm("geometry")
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: windowScene.interfaceOrientation.isPortrait ? .portrait : .landscape))
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
        guard !swallowsHardwareKeys else { return }
        super.pressesBegan(presses, with: event)
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
