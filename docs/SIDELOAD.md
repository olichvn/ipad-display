# Getting the app onto your iPad (free, no Mac)

This uses [AltStore](https://altstore.io) with a free Apple ID. No Apple
Developer Program membership, no Mac. The trade-off: apps signed this way
expire after **7 days** unless refreshed — AltStore can do that
automatically in the background, covered at the end.

## One-time setup

1. **Install iTunes** on this Windows PC (the regular Apple iTunes for
   Windows, from Apple's site, not the Microsoft Store version) — AltServer
   needs Apple's device drivers that ship with it.
2. **Install [AltServer for Windows](https://faq.altstore.io/getting-started/altserver-windows)**
   and run it. It sits in the system tray.
3. **Connect your iPad to this PC by USB-C** the first time (needed once,
   to pair it).
4. In the AltServer tray icon menu: **Install AltStore → (your iPad)**.
   It'll ask for your Apple ID and password — that's between you and
   Apple's servers directly (AltServer authenticates with Apple, not with
   me), used only to generate a free signing certificate.
5. On the iPad: **Settings → General → VPN & Device Management** → trust
   the developer certificate for your Apple ID.
6. Open the new **AltStore** app on the iPad once to confirm it works.

## Installing a build of this app

1. Push this repo to GitHub (see main README) so GitHub Actions builds it,
   or trigger the workflow manually from the **Actions** tab → "Build IPA"
   → **Run workflow**.
2. Once it finishes (~5–10 min), open the workflow run and download the
   **ExternalBrowser-ipa** artifact — it's a `.zip` containing
   `ExternalBrowser.ipa`. Unzip it on this PC.
3. With AltServer running and the iPad on the **same WiFi network** as
   this PC (USB works too): in AltServer's tray menu choose
   **My Apps → (your iPad)**, or drag `ExternalBrowser.ipa` onto the
   AltServer tray icon.
   - Alternatively, open the **AltStore** app on the iPad itself, go to
     **My Apps → +** in the top-left, and pick the `.ipa` — this requires
     AltServer to be running and reachable on the same WiFi network.
4. The app installs like any normal app — find "External Browser" on the
   Home Screen.

## Keeping it alive past 7 days

Free Apple ID signatures expire weekly. AltStore handles renewal for you
automatically **if**:
- The iPad has WiFi access to a network AltServer can reach (it doesn't
  need to be this exact PC every time — AltServer just needs to be
  running somewhere on the same network occasionally), **or**
- You plug the iPad into this PC every so often with AltServer running.

If a week passes with no refresh, the app icon goes grey/won't launch —
just reopen AltStore on the iPad (or reconnect to AltServer) to refresh it
manually; no need to reinstall or lose any browser data.

## If you'd rather pay $99/year and skip all of this

Apple Developer Program membership gets you TestFlight instead: 90-day
builds, install/update entirely from the TestFlight app, no PC needed at
install time. Say the word and I'll switch the CI pipeline to build a
TestFlight upload instead — you'd just need to enroll at
developer.apple.com yourself (identity verification + payment, which I
can't do on your behalf).
