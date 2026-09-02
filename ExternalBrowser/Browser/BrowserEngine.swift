import WebKit
import Combine
import UIKit

/// One persistent WKWebView per tab, never recreated, so that switching
/// displays, toggling full-screen or switching tabs never reloads a page
/// or loses session state — a remote-desktop session in one tab keeps
/// running while another tab is in front.
final class BrowserEngine: NSObject, ObservableObject {
    static let shared = BrowserEngine()

    /// Deliberately small. Each tab is a full web process, and this is a
    /// 2018 iPad: a remote-desktop session plus a couple of heavy sites
    /// is already meaningful memory pressure.
    static let maxTabs = 3

    @Published private(set) var state = BrowserState()
    @Published private(set) var tabs: [BrowserTab] = []
    @Published private(set) var activeTabIndex = 0

    /// The active tab's page view. Exposed under the old single-web-view
    /// name so everything that drives "the page" — InputRelay, BrowserView,
    /// navigation — keeps working without knowing about tabs.
    var webView: WKWebView {
        tabs[activeTabIndex].webView
    }

    /// Small web view hosting the navigation toolbar. Separate from the
    /// page so it can be clicked/typed into by InputRelay's synthetic
    /// events (a native SwiftUI toolbar is unreachable on this scene).
    let toolbarWebView: WKWebView
    static let toolbarHeight: CGFloat = 44

    private override init() {
        // The toolbar lives in its own small web view stacked ABOVE the
        // page rather than as an overlay inside it. An in-page fixed bar
        // covered the top of every site, and padding the body can't fix
        // that: a page's own position:fixed header (google.com has one)
        // ignores body padding and still renders underneath. Giving the
        // toolbar its own view means the page simply never extends under
        // it. It's browser chrome, not a second browsing context — still
        // exactly one page-hosting web view.
        let toolbarConfiguration = WKWebViewConfiguration()
        // Same user scripts as the page: the cursor overlay must exist in
        // this document too, or the pointer disappears when it moves over
        // the toolbar. Registering them here (rather than evaluating once
        // at attach time) means they survive the initial load — an
        // evaluateJavaScript call racing loadHTMLString is discarded when
        // the new document commits.
        for source in [InputRelay.cursorBootstrapScript, InputRelay.keyboardBehaviorScript] {
            let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            toolbarConfiguration.userContentController.addUserScript(script)
        }
        let toolbarWebView = WKWebView(frame: .zero, configuration: toolbarConfiguration)
        toolbarWebView.scrollView.isScrollEnabled = false
        toolbarWebView.scrollView.contentInsetAdjustmentBehavior = .never

        self.toolbarWebView = toolbarWebView
        super.init()

        toolbarConfiguration.userContentController.add(self, name: "extBrowserBridge")
        toolbarWebView.loadHTMLString(BrowserEngine.toolbarHTML, baseURL: nil)

        tabs = [makeTab()]
        activeTabIndex = 0
    }

    // MARK: - Tabs

    /// Every tab shares the default website data store, so cookies and
    /// logins are common across them, and carries the same user scripts —
    /// the cursor overlay has to exist in each tab's document or the
    /// pointer vanishes after switching.
    private func makeTab() -> BrowserTab {
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
        // cursor InputRelay depends on.
        for source in [InputRelay.cursorBootstrapScript, InputRelay.keyboardBehaviorScript] {
            let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            configuration.userContentController.addUserScript(script)
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        webView.uiDelegate = self

        let tab = BrowserTab(webView: webView)
        observe(tab: tab)
        return tab
    }

    private func observe(tab: BrowserTab) {
        tab.titleObservation = tab.webView.observe(\.title, options: [.new]) { [weak self, weak tab] webView, _ in
            DispatchQueue.main.async {
                guard let self = self, let tab = tab else { return }
                tab.displayTitle = BrowserTab.shortTitle(for: webView)
                if self.isActive(tab) {
                    self.state.title = webView.title
                }
                self.syncToolbarTabs()
            }
        }
        tab.urlObservation = tab.webView.observe(\.url, options: [.new]) { [weak self, weak tab] webView, _ in
            DispatchQueue.main.async {
                tab?.displayTitle = BrowserTab.shortTitle(for: webView)
                guard let self = self, let tab = tab, self.isActive(tab) else { return }
                self.state.url = webView.url
                self.state.canGoBack = webView.canGoBack
                self.state.canGoForward = webView.canGoForward
                self.syncToolbarURL()
                self.syncToolbarTabs()
            }
        }
        tab.progressObservation = tab.webView.observe(\.estimatedProgress, options: [.new]) { [weak self, weak tab] webView, _ in
            DispatchQueue.main.async {
                guard let self = self, let tab = tab, self.isActive(tab) else { return }
                self.state.progress = webView.estimatedProgress
            }
        }
    }

    private func isActive(_ tab: BrowserTab) -> Bool {
        tabs.indices.contains(activeTabIndex) && tabs[activeTabIndex] === tab
    }

    func addTab() {
        guard tabs.count < BrowserEngine.maxTabs else { return }
        tabs.append(makeTab())
        selectTab(tabs.count - 1)
    }

    func selectTab(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeTabIndex = index

        let webView = tabs[index].webView
        state.url = webView.url
        state.title = webView.title
        state.canGoBack = webView.canGoBack
        state.canGoForward = webView.canGoForward
        state.isLoading = webView.isLoading

        ensureDocumentLoaded()
        syncToolbarURL()
        syncToolbarTabs()
        // The relay tracks which view it is driving; tell it the page
        // underneath has changed.
        InputRelay.shared.activePageChanged()
    }

    func closeTab(_ index: Int) {
        guard tabs.count > 1, tabs.indices.contains(index) else { return }
        tabs.remove(at: index)
        selectTab(min(activeTabIndex, tabs.count - 1))
    }

    /// Pushes the current URL into the toolbar web view's address field.
    private func syncToolbarURL() {
        guard let urlString = state.url?.absoluteString else { return }
        let escaped = urlString.replacingOccurrences(of: "'", with: "\\'")
        toolbarWebView.evaluateJavaScript("window.__extbrowserSetURL && window.__extbrowserSetURL('\(escaped)')", completionHandler: nil)
    }

    private func syncToolbarTabs() {
        let titles = tabs.map { $0.displayTitle }
        guard let data = try? JSONSerialization.data(withJSONObject: titles),
              let json = String(data: data, encoding: .utf8) else { return }
        let canAdd = tabs.count < BrowserEngine.maxTabs
        toolbarWebView.evaluateJavaScript(
            "window.__extbrowserSetTabs && window.__extbrowserSetTabs(\(json), \(activeTabIndex), \(canAdd))",
            completionHandler: nil)
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

    /// Guarantees the page has a live document, loading the homepage
    /// (about:blank by default) if nothing has been opened yet. The input
    /// relay drives the page by dispatching into its JavaScript context,
    /// so with no document loaded there is nothing to dispatch into and
    /// the mouse appears dead until a URL is entered by hand.
    func ensureDocumentLoaded() {
        guard webView.url == nil else { return }
        let homepage = AppSettings.shared.homepage.trimmingCharacters(in: .whitespacesAndNewlines)
        load(urlString: homepage.isEmpty ? "about:blank" : homepage)
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

// MARK: - WKScriptMessageHandler

extension BrowserEngine: WKScriptMessageHandler {
    /// Receives messages from the toolbar web view so its buttons and
    /// URL field can drive real navigation.
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "navigate":
            if let value = body["value"] as? String { load(urlString: value) }
        case "back": goBack()
        case "forward": goForward()
        case "reload": reload()
        case "newTab": addTab()
        case "selectTab":
            if let index = body["value"] as? Int { selectTab(index) }
        case "closeTab":
            if let index = body["value"] as? Int { closeTab(index) }
        default: break
        }
    }

    /// Standalone document for the toolbar web view: back/forward/reload
    /// plus an editable URL field. Reachable via InputRelay's synthetic
    /// click/keyboard events because it's real DOM (a native SwiftUI
    /// toolbar would be unreachable on this input-less scene). Talks back
    /// to Swift via the "extBrowserBridge" message handler.
    static let toolbarHTML = """
    <!DOCTYPE html>
    <html>
    <head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
    <body style="margin:0;height:44px;background:#1c1c1e;display:flex;align-items:center;padding:0 8px;gap:8px;font-family:-apple-system,sans-serif;overflow:hidden;">
      <button id="back" style="width:36px;height:32px;border-radius:6px;border:none;background:#3a3a3c;color:white;font-size:16px;">&#9664;</button>
      <button id="fwd" style="width:36px;height:32px;border-radius:6px;border:none;background:#3a3a3c;color:white;font-size:16px;">&#9654;</button>
      <button id="reload" style="width:36px;height:32px;border-radius:6px;border:none;background:#3a3a3c;color:white;font-size:16px;">&#8635;</button>
      <input id="url" type="text" spellcheck="false" autocomplete="off"
             style="width:45%;flex:0 0 auto;height:32px;border-radius:6px;border:none;padding:0 10px;font-size:15px;">
      <div id="tabs" style="flex:1;display:flex;align-items:center;gap:6px;overflow:hidden;"></div>
      <script>
        function send(action, value){
          if (window.webkit && window.webkit.messageHandlers.extBrowserBridge) {
            window.webkit.messageHandlers.extBrowserBridge.postMessage(
              value === undefined ? {action:action} : {action:action, value:value});
          }
        }
        var url = document.getElementById('url');
        document.getElementById('back').addEventListener('click', function(){ send('back'); });
        document.getElementById('fwd').addEventListener('click', function(){ send('forward'); });
        document.getElementById('reload').addEventListener('click', function(){ send('reload'); });

        // Explicit editing flag rather than checking document.activeElement:
        // focus is sticky, so once this field had been clicked every later
        // navigation was skipped and the bar kept showing a stale URL while
        // the iPad's own field stayed correct.
        var editing = false;
        url.addEventListener('input', function(){ editing = true; });
        url.addEventListener('blur', function(){ editing = false; });
        url.addEventListener('keydown', function(e){
          if (e.key === 'Enter') { editing = false; send('navigate', url.value); url.blur(); }
        });
        window.__extbrowserSetURL = function(newURL){
          if (!editing) { url.value = newURL; }
        };

        var tabsEl = document.getElementById('tabs');
        window.__extbrowserSetTabs = function(tabs, activeIndex, canAdd){
          tabsEl.innerHTML = '';
          tabs.forEach(function(t, i){
            var active = (i === activeIndex);
            var b = document.createElement('button');
            b.style.cssText = 'max-width:150px;height:32px;border-radius:6px;border:none;padding:0 8px;font-size:13px;' +
              'white-space:nowrap;overflow:hidden;text-overflow:ellipsis;' +
              (active ? 'background:#f5f7fa;color:#1c1c1e;' : 'background:#3a3a3c;color:#d0d4dc;');
            b.textContent = t || ('Tab ' + (i + 1));
            b.addEventListener('click', function(){ send('selectTab', i); });
            tabsEl.appendChild(b);

            if (tabs.length > 1) {
              var x = document.createElement('button');
              x.textContent = '\\u00D7';
              x.style.cssText = 'width:24px;height:32px;border-radius:6px;border:none;background:#3a3a3c;color:#d0d4dc;font-size:14px;';
              x.addEventListener('click', function(){ send('closeTab', i); });
              tabsEl.appendChild(x);
            }
          });
          if (canAdd) {
            var plus = document.createElement('button');
            plus.textContent = '+';
            plus.style.cssText = 'width:32px;height:32px;border-radius:6px;border:none;background:#3a3a3c;color:white;font-size:18px;';
            plus.addEventListener('click', function(){ send('newTab'); });
            tabsEl.appendChild(plus);
          }
        };
      </script>
    </body>
    </html>
    """
}

// MARK: - WKNavigationDelegate

extension BrowserEngine: WKNavigationDelegate {
    /// All tabs share this delegate, so every callback ignores anything
    /// that isn't the tab currently on screen — a background tab loading
    /// must not overwrite the visible tab's status or address bar.
    private func isFrontmost(_ webView: WKWebView) -> Bool {
        tabs.indices.contains(activeTabIndex) && tabs[activeTabIndex].webView === webView
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard isFrontmost(webView) else { return }
        state.isLoading = true
        state.errorMessage = nil
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard isFrontmost(webView) else { return }
        state.url = webView.url
        syncToolbarURL()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncToolbarTabs()
        guard isFrontmost(webView) else { return }
        state.isLoading = false
        state.progress = 1
        state.canGoBack = webView.canGoBack
        state.canGoForward = webView.canGoForward
        syncToolbarURL()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard isFrontmost(webView) else { return }
        handle(error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard isFrontmost(webView) else { return }
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
    /// Requests to open a new window (target="_blank", window.open) go to
    /// a new tab when there's room, and otherwise load in place. Either
    /// way no second window is ever created — the external display shows
    /// exactly one page at a time.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }

        if tabs.count < BrowserEngine.maxTabs, let url = navigationAction.request.url {
            addTab()
            self.webView.load(URLRequest(url: url))
        } else {
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
