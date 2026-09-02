import WebKit

/// One browsing context. Each tab keeps its own web view alive for the
/// lifetime of the app, so switching tabs never reloads a page — a
/// remote-desktop session in one tab stays connected while another tab
/// is in front, which is the whole point of having tabs here.
final class BrowserTab {
    let webView: WKWebView

    /// Short label for the tab strip: the site's host is more useful and
    /// far more stable than a page title, which can be long or empty.
    var displayTitle: String = "New Tab"

    var titleObservation: NSKeyValueObservation?
    var urlObservation: NSKeyValueObservation?
    var progressObservation: NSKeyValueObservation?

    init(webView: WKWebView) {
        self.webView = webView
    }

    static func shortTitle(for webView: WKWebView) -> String {
        if let host = webView.url?.host {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        if let title = webView.title, !title.isEmpty {
            return title
        }
        return "New Tab"
    }
}
