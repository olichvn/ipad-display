import GameController
import WebKit
import UIKit

/// Reads raw mouse/keyboard input via the GameController framework and
/// forwards it into the page as synthetic DOM events.
///
/// This exists because the external-display scene (see
/// ExternalDisplaySceneDelegate) is, by Apple's design, incapable of
/// receiving any touch/mouse/keyboard input on this device's chip
/// (confirmed on hardware — non-M-series iPads cannot get a genuinely
/// interactive extended display through the normal windowing system).
/// GCMouse/GCKeyboard read raw HID input independent of that routing —
/// the same mechanism full-screen games use for mouse-look controls —
/// which lets us drive the page directly regardless of which window
/// nominally has "focus."
///
/// Known limitation: dispatched events are synthetic (`isTrusted ==
/// false`). Sites that specifically distinguish trusted from synthetic
/// events (some anti-automation/anti-bot checks) won't respond
/// correctly. This is expected to work well for the primary target
/// use case (a Guacamole remote-desktop session, which just wants a
/// raw mouse/keyboard event stream to relay onward) and for ordinary
/// links/scrolling/forms; it's the wrong tool for sites that actively
/// resist automation.
final class InputRelay {
    static let shared = InputRelay()

    private weak var webView: WKWebView?
    private var cursor: CGPoint = .zero
    private var shiftDown = false

    private var mouse: GCMouse?
    private var keyboard: GCKeyboard?

    private init() {}

    func attach(to webView: WKWebView) {
        self.webView = webView
        cursor = CGPoint(x: webView.bounds.midX, y: webView.bounds.midY)
        injectCursorScript()

        NotificationCenter.default.addObserver(self, selector: #selector(mouseConnected(_:)), name: .GCMouseDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(mouseDisconnected(_:)), name: .GCMouseDidDisconnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardConnected(_:)), name: .GCKeyboardDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDisconnected(_:)), name: .GCKeyboardDidDisconnect, object: nil)

        if let existingMouse = GCMouse.mice().first {
            configure(mouse: existingMouse)
        }
        if let existingKeyboard = GCKeyboard.coalesced {
            configure(keyboard: existingKeyboard)
        }
    }

    func detach() {
        mouse?.mouseInput?.mouseMovedHandler = nil
        keyboard?.keyboardInput?.keyChangedHandler = nil
        NotificationCenter.default.removeObserver(self)
        mouse = nil
        keyboard = nil
        webView = nil
    }

    @objc private func mouseConnected(_ note: Notification) {
        guard let m = note.object as? GCMouse else { return }
        configure(mouse: m)
    }

    @objc private func mouseDisconnected(_ note: Notification) {
        mouse = nil
    }

    @objc private func keyboardConnected(_ note: Notification) {
        guard let k = note.object as? GCKeyboard else { return }
        configure(keyboard: k)
    }

    @objc private func keyboardDisconnected(_ note: Notification) {
        keyboard = nil
    }

    private func configure(mouse: GCMouse) {
        self.mouse = mouse
        guard let input = mouse.mouseInput else { return }

        input.mouseMovedHandler = { [weak self] _, deltaX, deltaY in
            self?.handleMouseMoved(deltaX: CGFloat(deltaX), deltaY: CGFloat(deltaY))
        }
        input.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.dispatchMouse(type: pressed ? "mousedown" : "mouseup", button: 0)
        }
        input.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.dispatchMouse(type: pressed ? "mousedown" : "mouseup", button: 2)
        }
        input.scroll.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.handleScroll(deltaX: CGFloat(xValue), deltaY: CGFloat(yValue))
        }
    }

    private func configure(keyboard: GCKeyboard) {
        self.keyboard = keyboard
        keyboard.keyboardInput?.keyChangedHandler = { [weak self] _, _, keyCode, pressed in
            self?.handleKey(keyCode: keyCode, pressed: pressed)
        }
    }

    private func handleMouseMoved(deltaX: CGFloat, deltaY: CGFloat) {
        guard let webView = webView else { return }
        let bounds = webView.bounds
        // GameController reports +Y as up; DOM/screen coordinates are +Y down.
        cursor.x = min(max(0, cursor.x + deltaX), bounds.width)
        cursor.y = min(max(0, cursor.y - deltaY), bounds.height)
        dispatchMouse(type: "mousemove", button: 0)
    }

    private func handleScroll(deltaX: CGFloat, deltaY: CGFloat) {
        guard let webView = webView else { return }
        // Tuned down from an initial 40 — that made the wheel scroll the
        // page far too fast (each tick reports a larger value than a
        // typical analog-stick-style delta).
        let sensitivity: CGFloat = 6
        var offset = webView.scrollView.contentOffset
        offset.x -= deltaX * sensitivity
        offset.y += deltaY * sensitivity
        offset.x = max(0, offset.x)
        offset.y = max(0, offset.y)
        webView.scrollView.setContentOffset(offset, animated: false)
    }

    private func dispatchMouse(type: String, button: Int) {
        guard let webView = webView else { return }
        let x = Int(cursor.x)
        let y = Int(cursor.y)
        let js = """
        (function(){
          var el = document.elementFromPoint(\(x), \(y)) || document.body;
          var ev = new MouseEvent('\(type)', {bubbles:true, cancelable:true, view:window, clientX:\(x), clientY:\(y), button:\(button)});
          el.dispatchEvent(ev);
          if ('\(type)' === 'mousedown') {
            var focusable = el.closest('input, textarea, [contenteditable="true"]');
            if (focusable) focusable.focus();
            var clickEv = new MouseEvent('click', {bubbles:true, cancelable:true, view:window, clientX:\(x), clientY:\(y), button:\(button)});
            el.dispatchEvent(clickEv);
          }
          if (window.__extbrowserSetCursor) window.__extbrowserSetCursor(\(x), \(y));
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Bootstraps the synthetic cursor overlay. Registered as a
    /// WKUserScript (see BrowserEngine) so WebKit re-runs it on every
    /// navigation automatically — a one-off evaluateJavaScript() call
    /// only survives until the next page load wipes the DOM.
    static let cursorBootstrapScript = """
    (function(){
      if (document.getElementById('__extbrowser_cursor')) return;
      var c = document.createElement('div');
      c.id = '__extbrowser_cursor';
      c.style.position = 'fixed';
      c.style.top = '0'; c.style.left = '0';
      c.style.width = '0'; c.style.height = '0';
      c.style.zIndex = '2147483647';
      c.style.pointerEvents = 'none';
      c.innerHTML = '<svg width="20" height="20" viewBox="0 0 20 20" style="position:absolute;top:0;left:0;filter:drop-shadow(0 0 1px white)"><path d="M1 1 L1 15 L5 12 L8 18 L10.5 17 L7.5 11 L13 11 Z" fill="black"/></svg>';
      document.documentElement.appendChild(c);
      window.__extbrowserSetCursor = function(x, y){
        c.style.transform = 'translate(' + x + 'px,' + y + 'px)';
      };
    })();
    """

    private func injectCursorScript() {
        webView?.evaluateJavaScript(InputRelay.cursorBootstrapScript, completionHandler: nil)
    }

    private func handleKey(keyCode: GCKeyCode, pressed: Bool) {
        if KeyCodeMap.isShiftKey(keyCode) {
            shiftDown = pressed
            return
        }
        guard pressed, let mapped = KeyCodeMap.map(keyCode, shift: shiftDown) else { return }
        dispatchKey(domKey: mapped.domKey, char: mapped.char)
    }

    private func dispatchKey(domKey: String, char: Character?) {
        guard let webView = webView else { return }
        let escapedKey = domKey.replacingOccurrences(of: "'", with: "\\'")
        var js = """
        (function(){
          var el = document.activeElement || document.body;
          var down = new KeyboardEvent('keydown', {key:'\(escapedKey)', bubbles:true, cancelable:true});
          el.dispatchEvent(down);
        """
        if let char = char {
            let escapedChar = String(char).replacingOccurrences(of: "'", with: "\\'")
            js += """

              if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
                var start = el.selectionStart || el.value.length;
                var end = el.selectionEnd || el.value.length;
                el.value = el.value.slice(0, start) + '\(escapedChar)' + el.value.slice(end);
                el.selectionStart = el.selectionEnd = start + 1;
                el.dispatchEvent(new Event('input', {bubbles:true}));
              }
            """
        } else if domKey == "Backspace" {
            js += """

              if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
                var start = el.selectionStart || 0;
                var end = el.selectionEnd || 0;
                if (start === end && start > 0) { start -= 1; }
                el.value = el.value.slice(0, start) + el.value.slice(end);
                el.selectionStart = el.selectionEnd = start;
                el.dispatchEvent(new Event('input', {bubbles:true}));
              }
            """
        } else if domKey == "Enter" {
            js += """

              if ((el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') && el.form) {
                if (el.form.requestSubmit) { el.form.requestSubmit(); } else { el.form.submit(); }
              }
            """
        }
        js += """

          var up = new KeyboardEvent('keyup', {key:'\(escapedKey)', bubbles:true, cancelable:true});
          el.dispatchEvent(up);
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}
