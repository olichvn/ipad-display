# External Browser (iPad → USB-C External Display)

A minimal iPadOS app that turns an iPad Pro 11" (2018, USB-C) connected to a
USB-C dock/monitor into a full-screen web browsing workstation: the iPad
shows browser controls, the external monitor shows one full-screen
`WKWebView`. No tabs, no Safari/Chrome embedding, no mirroring.

## Status

**Phase 1 (external display detection) and Phase 2 (persistent WKWebView on
the external display) are implemented together** in this first build, so
they can be validated on real hardware in a single sideload. Per the
project spec, everything after this is deliberately gated on that
hardware test succeeding — see "Known risk" below.

Implemented so far:
- External display detection via `UIScreen` connect/disconnect notifications
  (`ExternalDisplay/ExternalDisplayManager.swift`)
- A dedicated `UIWindow` on the external screen, entirely separate from the
  iPad's own window — not mirrored
- One persistent `WKWebView` (`Browser/BrowserEngine.swift`) that is never
  recreated, with a real toolbar (back/forward/reload/URL) on the external
  display
- iPad controller UI showing connection status, resolution, and browser
  state (`Controller/ControllerView.swift`)
- Full-screen toggle, keyboard shortcuts (⌘L, ⌘R, ⌘\[, ⌘\], Esc), persistent
  cookies/storage, homepage + clear-data settings

Not yet built (waiting on Phase 1/2 hardware confirmation before continuing,
per spec section 38): further Microsoft 365 / general web-compatibility
testing pass, refined disconnect/reconnect polish.

## Stable fallback

Tag **`stable-1`** is a hardware-confirmed good build: mouse, keyboard,
modifier keys, the external toolbar, and scrolling all verified working
on the target iPad. If a later change misbehaves, go back to it:

```bash
git checkout stable-1
```

A copy of that build is also kept locally as
`build-artifacts/ExternalBrowser-STABLE.ipa` — sideload it directly to
recover without waiting for a rebuild.

## Security & battery notes

- **App Transport Security is set to allow arbitrary loads** (plain HTTP,
  not just HTTPS). This is deliberate and matches every third-party iOS
  browser (Chrome/Firefox for iOS do the same) — a general-purpose
  browser has to be able to load whatever URL the user types, including
  old HTTP-only sites. It does **not** weaken TLS certificate validation
  for HTTPS sites — that's enforced by WebKit independently of this
  setting. If you'd rather the browser refuse plain HTTP entirely
  (HTTPS-only), say so and I'll flip it.
- **JavaScript `alert`/`confirm`/`prompt` are shown as real dialogs** the
  user has to respond to — an earlier draft of this code auto-accepted
  `confirm()` calls and silently swallowed `alert()` messages, which
  would have let a page's JS treat an unseen "OK" as a real user
  decision. Fixed in `Browser/BrowserEngine.swift`.
- **No autoplaying media.** `WKWebViewConfiguration` is left at WebKit's
  default (`mediaTypesRequiringUserActionForPlayback = .all`), so video/
  audio needs a user tap before it plays — same as Safari. An earlier
  draft disabled that gate, which would have let any page's background
  video or ad autoplay at full volume and burn battery/CPU on load.
- **Exactly one `WKWebView` ever exists** — popup/`window.open()`
  requests load into the same view rather than spawning a hidden second
  web view, and nothing is preloaded speculatively. No timers or polling
  loops anywhere in the app; all state updates are event-driven (KVO on
  the web view, `UIScreen` connect/disconnect notifications), so there's
  nothing running when the app is idle.
- **No network code beyond `WKWebView` itself, no analytics, no
  telemetry, no third-party SDKs.** Cookies/site data persist via
  `WKWebsiteDataStore.default()` and are only cleared when you tap
  "Clear Website Data" in Settings — never automatically.

## Known risk — please test this first

There are two different public iPadOS APIs for driving a second screen:

1. **`UIScreen` + `UIWindow(frame:).screen = externalScreen`** — the
   classic approach, used here. Simpler, fewer exotic symbols to get
   wrong without a compiler to check my work against.
2. **`UIWindowScene` with an external-display session role** — the more
   "modern" scene-based approach the spec also mentions.

Both are public, documented APIs. I chose (1) because it's the
longer-standing and simplest option to hand-write correctly without being
able to compile/test locally (there's no Mac in this environment). The
one thing I can't verify without your hardware: **whether the mouse
pointer reaches the web page on the external monitor** with this
approach. If it doesn't, that's the signal to switch to approach (2) —
tell me and I'll rework `ExternalDisplayManager`.

## Building

You don't need Xcode yourself — see [`docs/SIDELOAD.md`](docs/SIDELOAD.md).
CI (`.github/workflows/build.yml`) runs on a macOS GitHub Actions runner,
regenerates the Xcode project from [`project.yml`](project.yml) with
[XcodeGen](https://github.com/yonaskolb/XcodeGen), builds an **unsigned**
`.ipa`, and uploads it as a build artifact. AltStore/AltServer does the
actual code-signing at install time using your own free Apple ID — no
Apple Developer Program membership or secrets needed in this repo.

## Project layout

```
ExternalBrowser/
├── App/                 AppDelegate, SceneDelegate (iPad's own scene)
├── ExternalDisplay/      ExternalDisplayManager — owns the second UIWindow
├── Browser/              BrowserState, BrowserEngine (the one WKWebView),
│                         BrowserView (external-display UI)
├── Controller/           ControllerView (iPad UI)
└── Settings/             AppSettings, SettingsView
```
