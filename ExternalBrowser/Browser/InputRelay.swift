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
/// false`), and browser *default actions* tied to trusted input (native
/// Tab focus movement, Shift+Arrow text selection, native form submit
/// on Enter) don't fire automatically — those are reimplemented here in
/// JS instead. Sites that specifically distinguish trusted from
/// synthetic events (some anti-automation checks) won't respond
/// correctly; that's expected to be irrelevant for the primary target
/// use case (a Guacamole remote-desktop session, which just wants a raw
/// mouse/keyboard event stream to relay onward).
final class InputRelay {
    static let shared = InputRelay()

    private weak var webView: WKWebView?
    private var cursor: CGPoint = .zero
    /// Cursor starts unpositioned: at attach() time the web view hasn't
    /// been laid out yet, so its bounds are still zero and centring on
    /// them would just pin the cursor to the top-left corner.
    private var cursorInitialized = false

    private var mouse: GCMouse?
    private var keyboard: GCKeyboard?

    private var shiftDown = false
    private var ctrlDown = false
    private var altDown = false
    private var metaDown = false

    private init() {}

    func attach(to webView: WKWebView) {
        self.webView = webView
        cursorInitialized = false
        webView.evaluateJavaScript(InputRelay.cursorBootstrapScript, completionHandler: nil)
        webView.evaluateJavaScript(InputRelay.keyboardBehaviorScript, completionHandler: nil)

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
        shiftDown = false; ctrlDown = false; altDown = false; metaDown = false
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

    // MARK: - Mouse

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
            // Axes came back swapped on hardware: physical vertical wheel
            // motion was reported as xValue, scrolling the page sideways.
            self?.handleScroll(deltaX: CGFloat(yValue), deltaY: CGFloat(xValue))
        }
    }

    private func handleMouseMoved(deltaX: CGFloat, deltaY: CGFloat) {
        guard let webView = webView else { return }
        let bounds = webView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        initializeCursorIfNeeded(in: bounds)

        // Without pointer lock the mouse still drives the iPad's own
        // system pointer, which the OS clamps to the iPad's screen — once
        // it hits an edge, no further deltas arrive in that direction.
        // Scaling by the ratio between the two screens means traversing
        // the iPad's screen traverses the whole external display, so the
        // tracked cursor can still reach every edge.
        let iPadBounds = UIScreen.main.bounds
        let scaleX = iPadBounds.width > 0 ? bounds.width / iPadBounds.width : 1
        let scaleY = iPadBounds.height > 0 ? bounds.height / iPadBounds.height : 1

        // GameController reports +Y as up; DOM/screen coordinates are +Y down.
        cursor.x = min(max(0, cursor.x + deltaX * scaleX), bounds.width)
        cursor.y = min(max(0, cursor.y - deltaY * scaleY), bounds.height)
        dispatchMouse(type: "mousemove", button: 0)
    }

    private var lastScrollTime: CFTimeInterval = 0
    private var settleWorkItem: DispatchWorkItem?

    private func handleScroll(deltaX: CGFloat, deltaY: CGFloat) {
        guard let webView = webView else { return }
        // Low sensitivity + inverted from the initial attempt, per
        // hardware feedback (was both too fast and backwards).
        let sensitivity: CGFloat = 2
        var offset = webView.scrollView.contentOffset
        offset.x += deltaX * sensitivity
        offset.y -= deltaY * sensitivity
        offset.x = max(0, offset.x)
        offset.y = max(0, offset.y)
        webView.scrollView.setContentOffset(offset, animated: false)

        // WKWebView's tile-based rendering can leave stale/blank content
        // after a burst of rapid, code-driven (non-gesture) scroll
        // updates — nudge it once scrolling settles to force a repaint.
        settleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.webView?.evaluateJavaScript("window.scrollBy(0,1);window.scrollBy(0,-1);", completionHandler: nil)
        }
        settleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func initializeCursorIfNeeded(in bounds: CGRect) {
        guard !cursorInitialized else { return }
        cursor = CGPoint(x: bounds.midX, y: bounds.midY)
        cursorInitialized = true
    }

    private func dispatchMouse(type: String, button: Int) {
        guard let webView = webView else { return }
        // A click before any movement would otherwise land at (0,0).
        initializeCursorIfNeeded(in: webView.bounds)
        let x = Int(cursor.x)
        let y = Int(cursor.y)
        let js = """
        (function(){
          var el = document.elementFromPoint(\(x), \(y)) || document.body;
          var opts = {bubbles:true, cancelable:true, view:window, clientX:\(x), clientY:\(y), button:\(button), shiftKey:\(shiftDown), ctrlKey:\(ctrlDown), altKey:\(altDown), metaKey:\(metaDown)};
          el.dispatchEvent(new MouseEvent('\(type)', opts));
          if ('\(type)' === 'mousedown') {
            var focusable = el.closest('input, textarea, [contenteditable="true"]');
            if (focusable) focusable.focus();
            el.dispatchEvent(new MouseEvent('click', opts));
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

    // MARK: - Keyboard

    private func configure(keyboard: GCKeyboard) {
        self.keyboard = keyboard
        keyboard.keyboardInput?.keyChangedHandler = { [weak self] _, _, keyCode, pressed in
            self?.handleKey(keyCode: keyCode, pressed: pressed)
        }
    }

    private func handleKey(keyCode: GCKeyCode, pressed: Bool) {
        if let modifier = KeyCodeMap.modifier(for: keyCode) {
            switch modifier.kind {
            case .shift: shiftDown = pressed
            case .control: ctrlDown = pressed
            case .alt: altDown = pressed
            case .meta: metaDown = pressed
            }
            dispatchKey(domKey: modifier.domKey, code: modifier.code, keyCode: modifier.keyCode, char: nil, pressed: pressed)
            return
        }
        guard let mapped = KeyCodeMap.map(keyCode, shift: shiftDown) else { return }
        dispatchKey(domKey: mapped.domKey, code: mapped.code, keyCode: mapped.keyCode, char: pressed ? mapped.char : nil, pressed: pressed)
    }

    private func dispatchKey(domKey: String, code: String, keyCode: Int, char: Character?, pressed: Bool) {
        guard let webView = webView else { return }
        let escapedKey = domKey.replacingOccurrences(of: "'", with: "\\'")
        let type = pressed ? "keydown" : "keyup"
        // KeyboardEvent's constructor accepts `code` directly, but
        // `keyCode`/`which` are read-only derived properties on modern
        // engines and silently ignored if passed in the init dict — force
        // them with defineProperty instead, since consumers like
        // Guacamole's keyboard handling check the legacy numeric codes
        // as well as (or instead of) `key`.
        var js = """
        (function(){
          var el = document.activeElement || document.body;
          var ev = new KeyboardEvent('\(type)', {key:'\(escapedKey)', code:'\(code)', bubbles:true, cancelable:true, shiftKey:\(shiftDown), ctrlKey:\(ctrlDown), altKey:\(altDown), metaKey:\(metaDown)});
          Object.defineProperty(ev, 'keyCode', {get:function(){return \(keyCode);}});
          Object.defineProperty(ev, 'which', {get:function(){return \(keyCode);}});
          el.dispatchEvent(ev);
        """
        if pressed, let char = char {
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
        } else if pressed && domKey == "Backspace" {
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
        } else if pressed && domKey == "Enter" {
            js += """

              if ((el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') && el.form) {
                if (el.form.requestSubmit) { el.form.requestSubmit(); } else { el.form.submit(); }
              }
            """
        }
        js += """

        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Reimplements the browser *default actions* that only fire for
    /// trusted (real hardware) keyboard events and are silently ignored
    /// for our synthetic ones: Tab moving focus between fields, and
    /// Shift+Arrow/Home/End extending a text selection.
    static let keyboardBehaviorScript = """
    (function(){
      if (window.__extbrowserKeyboardBehaviorInstalled) return;
      window.__extbrowserKeyboardBehaviorInstalled = true;

      function focusable(){
        return Array.prototype.slice.call(document.querySelectorAll(
          'input:not([disabled]):not([type=hidden]), textarea:not([disabled]), select:not([disabled]), button:not([disabled]), a[href], [tabindex]:not([tabindex="-1"])'
        )).filter(function(el){ return el.offsetParent !== null; });
      }

      document.addEventListener('keydown', function(e){
        if (e.key === 'Tab') {
          e.preventDefault();
          var items = focusable();
          var idx = items.indexOf(document.activeElement);
          var next = e.shiftKey
            ? items[(idx - 1 + items.length) % items.length]
            : items[(idx + 1) % items.length];
          if (next) next.focus();
          return;
        }

        var el = document.activeElement;
        var isText = el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA');
        var navKeys = ['ArrowLeft','ArrowRight','ArrowUp','ArrowDown','Home','End'];
        if (isText && e.shiftKey && navKeys.indexOf(e.key) !== -1) {
          var start = el.selectionStart || 0;
          var end = el.selectionEnd || 0;
          var anchor = (typeof el.__extbrowserAnchor === 'number') ? el.__extbrowserAnchor : start;
          var caret = (end !== anchor) ? end : start;
          if (e.key === 'ArrowLeft') caret = Math.max(0, caret - 1);
          if (e.key === 'ArrowRight') caret = Math.min(el.value.length, caret + 1);
          if (e.key === 'Home') caret = 0;
          if (e.key === 'End') caret = el.value.length;
          el.__extbrowserAnchor = anchor;
          el.selectionStart = Math.min(anchor, caret);
          el.selectionEnd = Math.max(anchor, caret);
        } else if (isText && !e.shiftKey && navKeys.indexOf(e.key) !== -1) {
          delete el.__extbrowserAnchor;
        }
      }, true);
    })();
    """
}
