import WebKit
import Combine
import UIKit

/// Owns the single persistent WKWebView for the app's one browsing session.
/// Created once and never recreated so that switching displays or toggling
/// full-screen never reloads the page or loses session state.
final class BrowserEngine: NSObject, ObservableObject {
    static let shared = BrowserEngine()

    @Published private(set) var state = BrowserState()

    let webView: WKWebView

    private var progressObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?

    private override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default() // persistent cookies/storage across launches
        configuration.allowsInlineMediaPlayback = true
        // Leave mediaTypesRequiringUserActionForPlayback at its default
        // (.all): autoplaying video/audio must wait for a user gesture,
        // same as Safari. Disabling that gate would let any page's
        // background video/ad autoplay at full volume on load — wasted
        // battery and an unpleasant surprise on a shared monitor.

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        self.webView = webView
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        observeWebView()
    }

    private func observeWebView() {
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.state.progress = webView.estimatedProgress
            }
        }
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.state.title = webView.title
            }
        }
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.state.url = webView.url
                self?.state.canGoBack = webView.canGoBack
                self?.state.canGoForward = webView.canGoForward
            }
        }
    }

    // MARK: - Navigation

    func load(urlString: String) {
        guard let url = BrowserEngine.normalize(urlString) else {
            state.errorMessage = "Invalid URL: \(urlString)"
            return
        }
        state.errorMessage = nil
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func stop() { webView.stopLoading() }

    func toggleFullScreen() {
        state.isFullScreen.toggle()
    }

    func setFullScreen(_ value: Bool) {
        state.isFullScreen = value
    }

    func clearWebsiteData(completion: @escaping () -> Void) {
        let dataStore = webView.configuration.websiteDataStore
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.fetchDataRecords(ofTypes: types) { records in
            dataStore.removeData(ofTypes: types, for: records) {
                completion()
            }
        }
    }

    /// Normalizes user-entered text into a loadable URL, e.g. "portal.azure.com" -> https://portal.azure.com/
    static func normalize(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        // No scheme: treat as https host (or path) unless it looks like a search query.
        let looksLikeHost = trimmed.contains(".") && !trimmed.contains(" ")
        if looksLikeHost, let url = URL(string: "https://\(trimmed)") {
            return url
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/search"
        components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components.url
    }
}

// MARK: - WKNavigationDelegate

extension BrowserEngine: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        state.isLoading = true
        state.errorMessage = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        state.isLoading = false
        state.progress = 1
        state.canGoBack = webView.canGoBack
        state.canGoForward = webView.canGoForward
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error: error)
    }

    private func handle(error: Error) {
        let nsError = error as NSError
        // Ignore benign cancellation (e.g. user navigated away before load finished).
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return }
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }

        state.isLoading = false
        state.errorMessage = nsError.localizedDescription
    }
}

// MARK: - WKUIDelegate

extension BrowserEngine: WKUIDelegate {
    /// The app has exactly one window and no tabs. Requests to open a new
    /// window (target="_blank", window.open, etc.) are loaded in the same
    /// WKWebView instead of spawning a second one.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard let presenter = topPresenter() else { completionHandler(); return }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        presenter.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard let presenter = topPresenter() else { completionHandler(false); return }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        presenter.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        guard let presenter = topPresenter() else { completionHandler(nil); return }
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        presenter.present(alert, animated: true)
    }

    /// JS dialogs are presented on whichever screen the page is actually
    /// visible on (usually the external display; falls back to the iPad
    /// controller if no external display is connected).
    private func topPresenter() -> UIViewController? {
        let window = ExternalDisplayManager.shared.externalWindow ?? UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
