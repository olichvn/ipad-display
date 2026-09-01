import UIKit
import Combine

/// Purely informational now: publishes whether a second screen is
/// physically connected and its resolution, for the iPad controller's
/// status panel. It no longer creates any window itself — the browser
/// window is a normal interactive SwiftUI WindowGroup (see
/// ExternalBrowserApp.swift) that the user drags onto the external
/// display using iPadOS's own windowing system, since the dedicated
/// external-display scene role turned out to accept no touch/mouse
/// input at all on real hardware.
final class ExternalDisplayManager: NSObject, ObservableObject {
    static let shared = ExternalDisplayManager()

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var displayName: String = ""
    @Published private(set) var pixelResolution: CGSize = .zero
    @Published private(set) var pointSize: CGSize = .zero

    private var started = false

    private override init() {
        super.init()
        start()
    }

    private func start() {
        guard !started else { return }
        started = true

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleChange), name: UIScreen.didConnectNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleChange), name: UIScreen.didDisconnectNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleChange), name: UIScreen.modeDidChangeNotification, object: nil)

        refresh()
    }

    @objc private func handleChange() {
        refresh()
    }

    private func refresh() {
        guard let screen = UIScreen.screens.first(where: { $0 != UIScreen.main }) else {
            isConnected = false
            displayName = ""
            pixelResolution = .zero
            pointSize = .zero
            return
        }
        pixelResolution = screen.currentMode?.size ?? screen.bounds.size
        pointSize = screen.bounds.size
        displayName = "External Display"
        isConnected = true
    }
}
