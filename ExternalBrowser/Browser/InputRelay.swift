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

    /// The page view is looked up live rather than captured at attach
    /// time, so switching tabs retargets input automatically with no
    /// re-attach. `attached` records whether a display is present at all.
    private var attached = false
    private var webView: WKWebView? {
        attached ? BrowserEngine.shared.webView : nil
    }
    private weak var toolbarWebView: WKWebView?
    /// Where synthetic keyboard input goes: whichever view was clicked
    /// last, so typing lands in the address bar after clicking it.
    private weak var activeWebView: WKWebView?

    /// Cursor position in external-display coordinates (y measured from
    /// the top of the toolbar, not the page).
    private var cursor: CGPoint = .zero
    /// Cursor starts unpositioned: at attach() time the web view hasn't
    /// been laid out yet, so its bounds are still zero and centring on
    /// them would just pin the cursor to the top-left corner.
    private var cursorInitialized = false

    private var lastClickTime: CFTimeInterval = 0
    private var lastClickPoint: CGPoint = .zero
    /// Which view is currently drawing the cursor overlay.
    private weak var lastCursorHost: WKWebView?

    /// Every connected mouse gets handlers, not just the first one
    /// reported. A Bluetooth keyboard's built-in trackpad and a USB mouse
    /// on the dock are two separate GCMouse devices, and the one that is
    /// listed first is not necessarily the one being used — handlers
    /// attached to the wrong device simply never fire.
    private var mice: [GCMouse] = []
    private var keyboard: GCKeyboard?
    private var observingDevices = false

    private var shiftDown = false
    private var ctrlDown = false
    private var altDown = false
    private var metaDown = false

    private init() {}

    func attach(to webView: WKWebView, toolbar toolbarWebView: WKWebView) {
        attached = true
        self.toolbarWebView = toolbarWebView
        self.activeWebView = webView
        cursorInitialized = false
        webView.evaluateJavaScript(InputRelay.cursorBootstrapScript, completionHandler: nil)
        toolbarWebView.evaluateJavaScript(InputRelay.cursorBootstrapScript, completionHandler: nil)
        webView.evaluateJavaScript(InputRelay.keyboardBehaviorScript, completionHandler: nil)

        startObservingDevices()

        for mouse in GCMouse.mice() {
            configure(mouse: mouse)
        }
        if let current = GCMouse.current {
            configure(mouse: current)
        }
        if let existingKeyboard = GCKeyboard.coalesced {
            configure(keyboard: existingKeyboard)
        }
    }

    /// Called when a different tab comes to the front: keyboard input has
    /// to follow the new page, the cursor overlay has to exist in that
    /// tab's document, and the arrow must be parked in the tab that just
    /// went away so it isn't left behind there.
    func activePageChanged() {
        guard attached, let page = webView else { return }
        lastCursorHost?.evaluateJavaScript(
            "window.__extbrowserSetCursor && window.__extbrowserSetCursor(-100,-100)",
            completionHandler: nil)
        lastCursorHost = nil
        activeWebView = page
        page.evaluateJavaScript(InputRelay.cursorBootstrapScript, completionHandler: nil)
        page.evaluateJavaScript(InputRelay.keyboardBehaviorScript, completionHandler: nil)
    }

    /// Device notifications are registered once and never torn down.
    /// They used to be removed in detach(), which opened a window — while
    /// the external display was disconnected — during which a mouse
    /// reconnecting on the dock went unnoticed. Switching a monitor
    /// between machines does exactly that, and the mouse stayed dead
    /// afterwards.
    private func startObservingDevices() {
        guard !observingDevices else { return }
        observingDevices = true
        NotificationCenter.default.addObserver(self, selector: #selector(mouseConnected(_:)), name: .GCMouseDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(mouseDisconnected(_:)), name: .GCMouseDidDisconnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardConnected(_:)), name: .GCKeyboardDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDisconnected(_:)), name: .GCKeyboardDidDisconnect, object: nil)
    }

    func detach() {
        mice.forEach { $0.mouseInput?.mouseMovedHandler = nil }
        keyboard?.keyboardInput?.keyChangedHandler = nil
        // Device observers deliberately stay registered — see
        // startObservingDevices().
        mice.removeAll()
        keyboard = nil
        attached = false
        toolbarWebView = nil
        activeWebView = nil
        lastCursorHost = nil
        shiftDown = false; ctrlDown = false; altDown = false; metaDown = false
    }

    @objc private func mouseConnected(_ note: Notification) {
        guard let m = note.object as? GCMouse else { return }
        configure(mouse: m)
    }

    @objc private func mouseDisconnected(_ note: Notification) {
        guard let m = note.object as? GCMouse else { return }
        mice.removeAll { $0 === m }
    }

    /// Always (re)binds to `GCKeyboard.coalesced` rather than the specific
    /// keyboard in the notification. That device merges every connected
    /// keyboard — Bluetooth and USB-on-the-dock alike — into one input
    /// source, so this covers both without hooking them individually. It
    /// can be nil at launch and is re-applied whenever a keyboard appears,
    /// which also covers a keyboard reconnecting with the dock.
    @objc private func keyboardConnected(_ note: Notification) {
        guard let coalesced = GCKeyboard.coalesced else { return }
        configure(keyboard: coalesced)
    }

    @objc private func keyboardDisconnected(_ note: Notification) {
        // Another keyboard may still be attached; rebind to whatever the
        // coalesced device covers now.
        keyboard = nil
        if let coalesced = GCKeyboard.coalesced {
            configure(keyboard: coalesced)
        }
    }

    // MARK: - Mouse

    private func configure(mouse: GCMouse) {
        guard !mice.contains(where: { $0 === mouse }) else { return }
        mice.append(mouse)
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

    /// Total interactive area: the page plus the toolbar strip above it.
    ///
    /// Prefers the external display's own size, which is known as soon as
    /// the scene connects. Deriving this from webView.bounds alone meant
    /// every mouse event was dropped until some later layout pass gave
    /// the view a non-zero size — in practice the mouse stayed dead until
    /// a page was loaded from the iPad.
    private var canvasSize: CGSize {
        let screenSize = ExternalDisplayManager.shared.pointSize
        if screenSize.width > 0, screenSize.height > 0 {
            return screenSize
        }
        guard let webView = webView else { return .zero }
        let pageBounds = webView.bounds
        return CGSize(width: pageBounds.width, height: pageBounds.height + toolbarOffset)
    }

    /// Height occupied by the toolbar web view, or 0 in full-screen mode.
    private var toolbarOffset: CGFloat {
        BrowserEngine.shared.state.isFullScreen ? 0 : BrowserEngine.toolbarHeight
    }

    /// Maps the cursor onto whichever web view it's over, converting to
    /// that view's local coordinates.
    ///
    /// Coordinates stay in view points here; the conversion to CSS pixels
    /// happens in the page itself, which divides by its own
    /// window.innerWidth. Scaling by a zoom value tracked on this side
    /// was unreliable — a page can be scaled by pageZoom, by its own
    /// viewport meta, or by about:blank's default layout width, and any
    /// disagreement made clicks land away from the cursor. Asking the
    /// page cannot disagree with the page.
    private func target() -> (webView: WKWebView, point: CGPoint)? {
        guard let webView = webView else { return nil }
        let offset = toolbarOffset
        if offset > 0, cursor.y < offset, let toolbar = toolbarWebView {
            return (toolbar, CGPoint(x: cursor.x, y: cursor.y))
        }
        return (webView, CGPoint(x: cursor.x, y: cursor.y - offset))
    }

    private func handleMouseMoved(deltaX: CGFloat, deltaY: CGFloat) {
        let size = canvasSize
        guard size.width > 0, size.height > 0 else { return }

        initializeCursorIfNeeded(in: CGRect(origin: .zero, size: size))

        // 1:1 with the physical mouse. (Deltas were briefly scaled by the
        // external/iPad screen ratio to work around the OS clamping its
        // own pointer at the iPad's screen edge; pointer lock removes that
        // clamping, so scaling only made the cursor move too fast.)
        // GameController reports +Y as up; DOM/screen coordinates are +Y down.
        cursor.x = min(max(0, cursor.x + deltaX), size.width)
        cursor.y = min(max(0, cursor.y - deltaY), size.height)
        dispatchMouse(type: "mousemove", button: 0)
    }

    private var lastScrollTime: CFTimeInterval = 0
    private var settleWorkItem: DispatchWorkItem?

    /// Scrolling goes through the DOM as a real `wheel` event rather than
    /// straight to the native scroll view. Moving contentOffset directly
    /// meant the page's JavaScript never learned a scroll had happened,
    /// so anything that handles its own wheel input — a Guacamole session
    /// forwarding it to the remote desktop, or an ordinary scrollable
    /// pane inside a page — was bypassed and the outer page scrolled
    /// instead. Only if nothing consumes the event do we scroll: first
    /// the nearest scrollable ancestor, then the page itself.
    private func handleScroll(deltaX: CGFloat, deltaY: CGFloat) {
        guard let (target, point) = target() else { return }
        // Low sensitivity + inverted from the initial attempt, per
        // hardware feedback (was both too fast and backwards).
        let sensitivity: CGFloat = 2
        let dx = deltaX * sensitivity
        // DOM deltaY is positive when scrolling down, the opposite sign
        // to the contentOffset arithmetic this replaced.
        let dy = -deltaY * sensitivity
        let viewWidth = max(target.bounds.width, 1)

        let js = """
        (function(){
        try {
          var f = (window.innerWidth > 0) ? (window.innerWidth / \(Int(viewWidth))) : 1;
          var x = Math.round(\(Int(point.x)) * f), y = Math.round(\(Int(point.y)) * f);
          var el = document.elementFromPoint(x, y) || document.body || document.documentElement;
          if (!el) return;
          var dx = \(dx), dy = \(dy);
          var opts = {bubbles:true, cancelable:true, view:window, clientX:x, clientY:y,
                      deltaX:dx, deltaY:dy, deltaMode:0};

          var consumed = !el.dispatchEvent(new WheelEvent('wheel', opts));
          if (!consumed) {
            // Older handlers (some remote-desktop clients included) still
            // listen for the legacy event instead of 'wheel'.
            var legacy = new MouseEvent('mousewheel', opts);
            try {
              Object.defineProperty(legacy, 'wheelDelta', {get:function(){return -dy * 3;}});
              Object.defineProperty(legacy, 'wheelDeltaY', {get:function(){return -dy * 3;}});
            } catch (e) {}
            consumed = !el.dispatchEvent(legacy);
          }
          if (consumed) return;

          // Nothing handled it: scroll the nearest scrollable ancestor,
          // falling back to the page.
          var node = el;
          while (node && node.nodeType === 1) {
            var s = window.getComputedStyle(node);
            var oy = s.overflowY, ox = s.overflowX;
            var scrollableY = (oy === 'auto' || oy === 'scroll') && node.scrollHeight > node.clientHeight;
            var scrollableX = (ox === 'auto' || ox === 'scroll') && node.scrollWidth > node.clientWidth;
            if ((dy !== 0 && scrollableY) || (dx !== 0 && scrollableX)) {
              node.scrollTop += dy;
              node.scrollLeft += dx;
              return;
            }
            node = node.parentElement;
          }
          window.scrollBy(dx, dy);
        } catch (e) {}
        })();
        """
        target.evaluateJavaScript(js, completionHandler: nil)

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
        // A click before any movement would otherwise land at (0,0).
        initializeCursorIfNeeded(in: CGRect(origin: .zero, size: canvasSize))
        guard let (target, point) = target() else { return }

        // Keep the cursor drawn in exactly one view: when it crosses
        // between the toolbar and the page, park the old view's arrow
        // off-screen so it doesn't linger there.
        if lastCursorHost !== target {
            lastCursorHost?.evaluateJavaScript(
                "window.__extbrowserSetCursor && window.__extbrowserSetCursor(-100,-100)",
                completionHandler: nil)
            lastCursorHost = target
        }

        var isDoubleClick = false
        if type == "mousedown" {
            let now = CACurrentMediaTime()
            let moved = hypot(cursor.x - lastClickPoint.x, cursor.y - lastClickPoint.y)
            isDoubleClick = (now - lastClickTime) < 0.4 && moved < 6
            lastClickTime = now
            lastClickPoint = cursor
            activeWebView = target
        }

        let viewWidth = max(target.bounds.width, 1)
        var js = """
        (function(){
          // The page converts points to its own CSS pixels: innerWidth
          // already reflects page zoom, viewport meta and about:blank's
          // default layout width, so this can't drift out of step with
          // whatever the page is actually doing.
          var f = (window.innerWidth > 0) ? (window.innerWidth / \(Int(viewWidth))) : 1;
          var x = Math.round(\(Int(point.x)) * f), y = Math.round(\(Int(point.y)) * f);
          var el = document.elementFromPoint(x, y) || document.body;
          if (!el) return;
          var opts = {bubbles:true, cancelable:true, view:window, clientX:x, clientY:y, button:\(button), shiftKey:\(shiftDown), ctrlKey:\(ctrlDown), altKey:\(altDown), metaKey:\(metaDown)};
          el.dispatchEvent(new MouseEvent('\(type)', opts));
          if ('\(type)' === 'mousedown') {
            var focusable = el.closest('input, textarea, [contenteditable="true"]');
            if (focusable) { focusable.focus(); }
            else if (document.activeElement && document.activeElement.blur) {
              // Clicking anywhere else drops focus, so the address bar
              // can't keep swallowing keystrokes after being clicked once.
              document.activeElement.blur();
            }
            el.dispatchEvent(new MouseEvent('click', opts));
          }
        """
        if isDoubleClick {
            // Synthetic events don't trigger the browser's own
            // double-click-selects-a-word behaviour, so do it by hand.
            js += """

              el.dispatchEvent(new MouseEvent('dblclick', opts));
              var field = el.closest('input, textarea');
              if (field && field.select) { field.select(); }
            """
        }
        js += """

          if (window.__extbrowserSetCursor) window.__extbrowserSetCursor(x, y, f);
        })();
        """
        target.evaluateJavaScript(js, completionHandler: nil)
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
      c.style.transformOrigin = '0 0';
      document.documentElement.appendChild(c);
      window.__extbrowserSetCursor = function(x, y, extraInverse){
        // The arrow lives inside the page, so it inherits the page's
        // zoom: a document with no viewport meta (about:blank) is laid
        // out narrow and scaled up on a large display, which blew the
        // cursor up to many times its intended size until a real site
        // loaded. Counter-scale to keep it visually constant. Only the
        // drawn size is adjusted — the coordinates are left alone so
        // click targeting is unchanged. extraInverse carries the page
        // zoom, which the visual viewport doesn't report.
        var scale = (window.visualViewport && window.visualViewport.scale) ? window.visualViewport.scale : 1;
        var inv = (scale > 0 ? (1 / scale) : 1) * (typeof extraInverse === 'number' ? extraInverse : 1);
        c.style.transform = 'translate(' + x + 'px,' + y + 'px) scale(' + inv + ')';
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
        if var modifier = KeyCodeMap.modifier(for: keyCode) {
            switch (modifier.kind, AppSettings.shared.altKeySource) {
            case (.meta, .command), (.meta, .both):
                modifier = KeyCodeMap.asAlt(modifier)
            case (.alt, .command):
                modifier = KeyCodeMap.asMeta(modifier)
            default:
                break // already correct
            }
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
        guard let webView = activeWebView ?? webView else { return }
        if pressed {
            var mods = ""
            if shiftDown { mods += "⇧" }
            if ctrlDown { mods += "⌃" }
            if altDown { mods += "⌥" }
            if metaDown { mods += "⌘" }
            PointerLockDiagnostics.shared.recordKey("\(mods)\(domKey) [\(code)/\(keyCode)]")
        }
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
                // Explicit null checks: a caret at index 0 is falsy, so
                // `selectionStart || length` would append at the end.
                var start = el.selectionStart != null ? el.selectionStart : el.value.length;
                var end = el.selectionEnd != null ? el.selectionEnd : el.value.length;
                el.value = el.value.slice(0, start) + '\(escapedChar)' + el.value.slice(end);
                el.selectionStart = el.selectionEnd = start + 1;
                el.dispatchEvent(new Event('input', {bubbles:true}));
              }
            """
        } else if pressed && domKey == "Backspace" {
            js += """

              if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
                var start = el.selectionStart != null ? el.selectionStart : el.value.length;
                var end = el.selectionEnd != null ? el.selectionEnd : el.value.length;
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
