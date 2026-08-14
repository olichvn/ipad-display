# Installing via SideStore + a self-hosted anisette server (VPS)

This is the free, "touch a computer exactly once, ever" path. It trades
one brief in-person setup step for indefinite, fully automatic renewal
over the internet via your own VPS — no local computer, no same-WiFi
requirement, nothing recurring for you to do.

Uses a **dedicated, secondary Apple ID** — never your main one. It's only
ever used as a bare signing credential; you never sign into it on the
iPad itself, and it has no connection to your main Apple ID, iCloud, or
App Store account. The app installs and runs on your iPad like any other
app regardless of which identity signed it.

## Step 0 — Create a throwaway Apple ID (you, anytime, from the iPad)

Go to [appleid.apple.com](https://appleid.apple.com) in Safari → **Create
Your Apple ID**. Use an email you don't mind associating with this (a
new/alias address is fine). No payment method needs to match your main
account. This identity is never used to sign into the iPad itself.

## Step 1 — One-time bootstrap (needs any computer + USB cable, once)

SideStore can't install itself — something has to sideload it the first
time. This is the one unavoidable in-person step.

1. On the borrowed computer: install **iTunes** (Windows) or nothing extra
   (Mac already has the drivers), then install
   [AltServer](https://altstore.io) for that OS.
2. Run AltServer, connect the iPad via USB.
3. AltServer tray/menu-bar icon → **Install AltStore** → your iPad. When
   prompted for an Apple ID, use the **throwaway ID from Step 0**, not
   your main one.
4. On the iPad: **Settings → General → VPN & Device Management** → trust
   the certificate for that Apple ID.
5. Open the new **AltStore** app once on the iPad to confirm it works.
6. In AltStore on the iPad, go to the **Browse** tab, add SideStore's
   source URL (`https://sidestore.io/sidestore.json` — confirm the
   current URL at [sidestore.io](https://sidestore.io), these can change),
   and install **SideStore** through AltStore.
7. Trust SideStore's certificate the same way as step 4, then open
   SideStore once.

At this point you can disconnect from the computer entirely — everything
from here on happens over the internet via your VPS.

## Step 2 — Self-hosted anisette server on your VPS

On the VPS (any Linux with Docker):

```bash
docker run -d \
  --name anisette-server \
  --restart unless-stopped \
  -p 6969:6969 \
  -v anisette-data:/home/Alcoholic/.config/anisette-v3/lib/ \
  dadoum/anisette-v3-server
```

This exposes port `6969`. Make sure your VPS firewall/security group
allows inbound TCP on that port, and use HTTPS/a reverse proxy (e.g.
Caddy or nginx with Let's Encrypt) in front of it if you want an
encrypted URL — SideStore doesn't strictly require TLS here, but it's
good practice for anything internet-facing.

Note the resulting URL, e.g. `http://YOUR_VPS_IP:6969` or
`https://anisette.yourdomain.com`.

## Step 3 — Point SideStore at your VPS

On the iPad, in SideStore: **Settings → Anisette Server** → enter your
VPS's URL from Step 2 instead of the default shared server. Self-hosting
avoids the shared community servers' rate limits and reliability issues.

## Step 4 — Install the browser app

1. Get `ExternalBrowser.ipa` onto the iPad (AirDrop from wherever it was
   built, or download it in Safari from the GitHub Actions artifact if
   you're signed into GitHub there).
2. Open SideStore, tap **My Apps → +**, pick the `.ipa`. It signs and
   installs using the throwaway Apple ID via your VPS's anisette server —
   no computer involved.

## Ongoing

SideStore refreshes the signature automatically before each 7-day window
closes, talking to your VPS. As long as the VPS stays up and the iPad has
internet access periodically, you never need to do anything manually
again — no computer, no reinstalling, no weekly chores.

If a refresh is ever missed and the app greys out, just open SideStore
once (on WiFi/cellular, no computer needed) to trigger a manual refresh.
