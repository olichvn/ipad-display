import SwiftUI
import WebKit

/// The view shown on the EXTERNAL monitor. Never shown on the iPad itself.
///
/// No native SwiftUI toolbar here on purpose — this scene accepts no
/// touch/mouse input from the OS (see ExternalDisplaySceneDelegate), so
/// a native toolbar would be permanently unreachable. Navigation
/// controls instead live in their own small web view stacked above the
/// page (see BrowserEngine.toolbarHTML), where InputRelay's synthetic
/// mouse/keyboard events can actually reach them.
struct BrowserView: View {
    @EnvironmentObject var engine: BrowserEngine

    var body: some View {
        VStack(spacing: 0) {
            if !engine.state.isFullScreen {
                WebViewRepresentable(webView: engine.toolbarWebView)
                    .frame(height: BrowserEngine.toolbarHeight)
            }
            TabPageView(tabs: engine.tabs, activeIndex: engine.activeTabIndex)
        }
        .ignoresSafeArea()
        .background(Color.black)
    }
}

/// Wraps a persistent WKWebView instance. makeUIView always returns the
/// same shared view (never a new one), so re-parenting this into a
/// freshly created SwiftUI hierarchy (e.g. after a display reconnect)
/// does not reload the page or lose session state.
struct WebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Hosts every tab's web view at once and shows only the active one.
///
/// Swapping which view a UIViewRepresentable returns doesn't work —
/// makeUIView is called once per view identity, so a changed web view
/// would never be installed. More importantly, all tabs stay in the view
/// hierarchy rather than being removed and re-added: a web view detached
/// from the hierarchy is liable to have its timers throttled, which would
/// put a background remote-desktop session at risk of dropping.
struct TabPageView: UIViewRepresentable {
    let tabs: [BrowserTab]
    let activeIndex: Int

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        for (index, tab) in tabs.enumerated() {
            let page = tab.webView
            if page.superview !== container {
                page.removeFromSuperview()
                page.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(page)
                NSLayoutConstraint.activate([
                    page.topAnchor.constraint(equalTo: container.topAnchor),
                    page.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                    page.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    page.trailingAnchor.constraint(equalTo: container.trailingAnchor)
                ])
            }
            page.isHidden = (index != activeIndex)
        }

        // Drop views belonging to closed tabs.
        let live = Set(tabs.map { ObjectIdentifier($0.webView) })
        for subview in container.subviews where !live.contains(ObjectIdentifier(subview)) {
            subview.removeFromSuperview()
        }

        if tabs.indices.contains(activeIndex) {
            container.bringSubviewToFront(tabs[activeIndex].webView)
        }
    }
}
