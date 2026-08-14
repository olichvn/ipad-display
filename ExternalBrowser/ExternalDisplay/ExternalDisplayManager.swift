import UIKit
import SwiftUI
import Combine

/// Watches for an external display (USB-C / DisplayPort Alt Mode monitor)
/// and owns the dedicated UIWindow shown on it. The external window is
/// entirely separate from the iPad's own window/scene: it is never a
/// mirror of the iPad UI, it hosts its own SwiftUI hierarchy (BrowserView).
///
/// Uses the classic UIScreen connect/disconnect notifications plus a
/// screen-owned UIWindow rather than a UIWindowScene external-display
/// role. This is the longest-standing, most broadly compatible public
/// API for driving a second interactive screen and is the safest choice
/// to validate first on real hardware (see Phase 1 proof-of-concept).
final class ExternalDisplayManager: NSObject, ObservableObject {
    static let shared = ExternalDisplayManager()

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var displayName: String = ""
    /// Native pixel resolution of the external display (e.g. 3840x2160).
    @Published private(set) var pixelResolution: CGSize = .zero
    /// Point size of the external display's UIScreen bounds, i.e. the
    /// coordinate space the external UIWindow actually lays out in.
    @Published private(set) var pointSize: CGSize = .zero

    private(set) var externalWindow: UIWindow?
    private var started = false

    private override init() { super.init() }

    func start() {
        guard !started else { return }
        started = true

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleScreenConnect(_:)),
            name: UIScreen.didConnectNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleScreenDisconnect(_:)),
            name: UIScreen.didDisconnectNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleModeChange(_:)),
            name: UIScreen.modeDidChangeNotification, object: nil)

        // If a display was already attached before the app finished
        // launching (e.g. iPad was already docked), pick it up now.
        if let existing = UIScreen.screens.first(where: { $0 != UIScreen.main }) {
            attach(to: existing)
        }
    }

    @objc private func handleScreenConnect(_ note: Notification) {
        guard let screen = note.object as? UIScreen else { return }
        attach(to: screen)
    }

    @objc private func handleScreenDisconnect(_ note: Notification) {
        guard let screen = note.object as? UIScreen, screen === externalWindow?.screen else { return }
        detach()
    }

    @objc private func handleModeChange(_ note: Notification) {
        guard let screen = note.object as? UIScreen, screen === externalWindow?.screen else { return }
        updatePublishedGeometry(for: screen)
    }

    private func attach(to screen: UIScreen) {
        selectNativeMode(for: screen)

        let window = UIWindow(frame: screen.bounds)
        window.screen = screen
        window.rootViewController = UIHostingController(
            rootView: BrowserView().environmentObject(BrowserEngine.shared)
        )
        window.isHidden = false
        externalWindow = window

        updatePublishedGeometry(for: screen)
        displayName = "External Display"
        isConnected = true

        let settings = AppSettings.shared
        if BrowserEngine.shared.state.url == nil, settings.autoActivateBrowser {
            BrowserEngine.shared.load(urlString: settings.homepage)
        }
        if settings.startInFullScreen {
            BrowserEngine.shared.setFullScreen(true)
        }
    }

    private func detach() {
        externalWindow?.isHidden = true
        externalWindow = nil
        isConnected = false
        displayName = ""
        pixelResolution = .zero
        pointSize = .zero
    }

    /// Picks the highest-resolution mode the display reports rather than
    /// hardcoding any resolution, per the requirement to use the
    /// monitor's own native/optimal geometry.
    private func selectNativeMode(for screen: UIScreen) {
        guard let best = screen.availableModes.max(by: {
            $0.size.width * $0.size.height < $1.size.width * $1.size.height
        }) else { return }
        if screen.currentMode?.size != best.size {
            screen.currentMode = best
        }
        externalWindow?.frame = screen.bounds
    }

    private func updatePublishedGeometry(for screen: UIScreen) {
        pixelResolution = screen.currentMode?.size ?? screen.bounds.size
        pointSize = screen.bounds.size
        externalWindow?.frame = screen.bounds
    }
}
