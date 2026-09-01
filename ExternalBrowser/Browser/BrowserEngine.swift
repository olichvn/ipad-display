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

        // Re-run on every navigation (not just once) — a page load
        // replaces the DOM and would otherwise wipe the synthetic
        // cursor / toolbar InputRelay and this class depend on.
        for source in [InputRelay.cursorBootstrapScript, InputRelay.keyboardBehaviorScript, BrowserEngine.toolbarBootstrapScript] {
            let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            configuration.userContentController.addUserScript(script)
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        self.webView = webView
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.configuration.userContentController.add(self, name: "extBrowserBridge")
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
                self?.syncToolbarURL()
            }
        }
    }

    /// Pushes the current URL/full-screen state into the in-page toolbar
    /// InputRelay's synthetic input can actually reach (see
    /// toolbarBootstrapScript below).
    private func syncToolbarURL() {
        guard let urlString = state.url?.absoluteString else { return }
        let escaped = urlString.replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("window.__extbrowserSetURL && window.__extbrowserSetURL('\(escaped)')", completionHandler: nil)
    }

    private func syncToolbarVisibility() {
        webView.evaluateJavaScript("window.__extbrowserSetToolbarVisible && window.__extbrowserSetToolbarVisible(\(!state.isFullScreen))", completionHandler: nil)
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
        syncToolbarVisibility()
    }

    func setFullScreen(_ value: Bool) {
        state.isFullScreen = value
        syncToolbarVisibility()
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

// MARK: - WKScriptMessageHandler

extension BrowserEngine: WKScriptMessageHandler {
    /// Receives messages from the in-page toolbar (toolbarBootstrapScript)
    /// so its buttons/URL field — reachable by InputRelay's synthetic
    /// input because they live in the page's own DOM — can drive real
    /// navigation.
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "navigate":
            if let value = body["value"] as? String { load(urlString: value) }
        case "back": goBack()
        case "forward": goForward()
        case "reload": reload()
        default: break
        }
    }

    /// In-page toolbar: back/forward/reload + an editable URL field, all
    /// reachable via InputRelay's synthetic click/keyboard events since
    /// (unlike a native SwiftUI toolbar) it's part of the page's own DOM.
    /// Talks back to Swift via the "extBrowserBridge" message handler.
    static let toolbarBootstrapScript = """
    (function(){
      if (document.getElementById('__extbrowser_toolbar')) return;
      var bar = document.createElement('div');
      bar.id = '__extbrowser_toolbar';
      bar.style.cssText = 'position:fixed;top:0;left:0;right:0;height:44px;background:rgba(28,28,30,0.92);display:flex;align-items:center;padding:0 8px;gap:8px;z-index:2147483646;font-family:-apple-system,sans-serif;';

      function makeButton(label){
        var b = document.createElement('button');
        b.textContent = label;
        b.style.cssText = 'width:36px;height:32px;border-radius:6px;border:none;background:#3a3a3c;color:white;font-size:16px;';
        return b;
      }

      var back = makeButton('\\u25C0');
      var fwd = makeButton('\\u25B6');
      var reload = makeButton('\\u21BB');
      var url = document.createElement('input');
      url.id = '__eb_url';
      url.type = 'text';
      url.value = location.href;
      url.style.cssText = 'flex:1;height:32px;border-radius:6px;border:none;padding:0 10px;font-size:15px;';

      bar.appendChild(back);
      bar.appendChild(fwd);
      bar.appendChild(reload);
      bar.appendChild(url);
      document.documentElement.appendChild(bar);

      function send(action, value){
        if (window.webkit && window.webkit.messageHandlers.extBrowserBridge) {
          window.webkit.messageHandlers.extBrowserBridge.postMessage(value === undefined ? {action:action} : {action:action, value:value});
        }
      }

      back.addEventListener('click', function(){ send('back'); });
      fwd.addEventListener('click', function(){ send('forward'); });
      reload.addEventListener('click', function(){ send('reload'); });
      url.addEventListener('keydown', function(e){
        if (e.key === 'Enter') { send('navigate', url.value); }
      });

      window.__extbrowserSetURL = function(newURL){
        if (document.activeElement !== url) { url.value = newURL; }
      };
      window.__extbrowserSetToolbarVisible = function(visible){
        bar.style.display = visible ? 'flex' : 'none';
      };
    })();
    """
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
        syncToolbarURL()
        syncToolbarVisibility()
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

    /// JS dialogs are presented from whichever window the web view is
    /// actually in right now, wherever the user has dragged it.
    private func topPresenter() -> UIViewController? {
        var top = webView.window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
