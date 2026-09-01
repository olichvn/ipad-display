import SwiftUI
import WebKit

/// The view shown on the EXTERNAL monitor. Never shown on the iPad itself.
///
/// No native SwiftUI toolbar here on purpose — this scene accepts no
/// touch/mouse input from the OS (see ExternalDisplaySceneDelegate), so
/// a native toolbar would be permanently unreachable. Navigation
/// controls instead live inside the page's own DOM (see
/// BrowserEngine.toolbarBootstrapScript), where InputRelay's synthetic
/// mouse/keyboard events can actually reach them.
struct BrowserView: View {
    @EnvironmentObject var engine: BrowserEngine

    var body: some View {
        WebViewRepresentable(webView: engine.webView)
            .ignoresSafeArea()
            .background(Color.black)
    }
}

/// Wraps the single persistent WKWebView instance. makeUIView always
/// returns the same shared view (never a new one), so re-parenting this
/// into a freshly created SwiftUI hierarchy (e.g. after a display
/// reconnect) does not reload the page or lose session state.
struct WebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
