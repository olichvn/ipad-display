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

/// Keeps the mouse off the iPad's own UI while the external display is in
/// use.
///
/// This deliberately does NOT use pointer lock. `prefersPointerLocked` is
/// only re-evaluated by UIKit on an app activation transition, and there
/// is no API to trigger one — on hardware that meant lock never engaged
/// from a cold start and the only fix was pulling Control Center down and
/// back up, every launch. Instead the two things lock was wanted for are
/// solved directly: mouse events are swallowed here (see
/// MouseBlockingView) so stray clicks can't operate the iPad UI, and
/// InputRelay scales its deltas so the cursor still reaches every edge of
/// the external display despite the system pointer being clamped to the
/// iPad's screen.
final class PointerLockingHostingController<Content: View>: UIHostingController<Content> {

    private let mouseBlocker = MouseBlockingView()

    override func viewDidLoad() {
        super.viewDidLoad()

        mouseBlocker.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mouseBlocker)
        NSLayoutConstraint.activate([
            mouseBlocker.topAnchor.constraint(equalTo: view.topAnchor),
            mouseBlocker.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mouseBlocker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mouseBlocker.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        updateMouseBlocking()

        for name in [AppSettings.pointerLockPreferenceChanged, ExternalDisplayManager.connectionChanged] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(updateMouseBlocking), name: name, object: nil)
        }
    }

    @objc private func updateMouseBlocking() {
        mouseBlocker.isHidden = !(AppSettings.shared.pointerLockEnabled && ExternalDisplayManager.shared.isConnected)
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

/// Invisible overlay that swallows mouse/trackpad input on the iPad while
/// the external display is being driven, so a click meant for the page
/// can't press a button here — previously a click anywhere on the
/// external display also activated whatever the iPad's own pointer
/// happened to be resting on.
///
/// Finger touches pass straight through, so the controls underneath
/// (Capture Mouse, Full Screen, Settings) remain usable — that matters,
/// since turning capture off has to stay possible when the mouse is
/// misbehaving.
final class MouseBlockingView: UIView, UIPointerInteractionDelegate {

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        addInteraction(UIPointerInteraction(delegate: self))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        addInteraction(UIPointerInteraction(delegate: self))
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden else { return nil }
        if let touch = event?.allTouches?.first, touch.type == .indirectPointer {
            return self // absorb it
        }
        return nil // finger touches fall through to the UI below
    }

    /// Hides the iPad's own pointer over this view, so only the cursor
    /// drawn on the external display is visible.
    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        UIPointerStyle.hidden()
    }
}
