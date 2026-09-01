import SwiftUI

/// Two ordinary windows, both fully interactive: "Controller" stays on
/// the iPad, "Browser" is meant to be dragged onto the external display
/// using iPadOS's own windowing system. Deliberately NOT using the
/// `.windowExternalDisplayNonInteractive` scene role — that role is
/// real, but (confirmed on real hardware) accepts no touch/mouse input
/// at all, which is disqualifying for a browser you need to click and
/// scroll. A plain interactive window works with mouse/keyboard/touch
/// regardless of which physical screen it ends up on.
@main
struct ExternalBrowserApp: App {
    var body: some Scene {
        WindowGroup("Controller", id: "controller") {
            ControllerView()
                .environmentObject(BrowserEngine.shared)
                .environmentObject(ExternalDisplayManager.shared)
        }

        WindowGroup("Browser", id: "browser") {
            BrowserView()
                .environmentObject(BrowserEngine.shared)
        }
    }
}
