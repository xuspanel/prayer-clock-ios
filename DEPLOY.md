# Prayer Clock Remote — Deployment & Architecture Guide (`DEPLOY.md`)

## 1. Domain & DNS Verification

- **Domain:** `prayer.xus.me`
- **Public IPv4 of VPS:** `132.145.70.205`

Verified with:
```bash
$ dig +short prayer.xus.me
132.145.70.205
$ curl -s4 ifconfig.me
132.145.70.205
```

---

## 2. Port Selection & Proof of Availability

- **Chosen Loopback Port:** `24740` (`127.0.0.1:24740`)

### Commands Executed to Prove Port `24740` Was Free

```bash
$ ss -tlnp | grep ':24740\b' || echo "TCP 24740 is not listening"
TCP 24740 is not listening

$ ss -ulnp | grep ':24740\b' || echo "UDP 24740 is not listening"
UDP 24740 is not listening

$ grep -R 24740 /etc/nginx /etc/caddy /etc/systemd 2>/dev/null || echo "24740 not referenced in /etc/nginx /etc/caddy /etc/systemd"
24740 not referenced in /etc/nginx /etc/caddy /etc/systemd

$ ufw status
Status: active
To                         Action      From
--                         ------      ----
OpenSSH                    ALLOW       Anywhere
22/tcp                     ALLOW       Anywhere
5432/tcp                   ALLOW       Anywhere
5432                       ALLOW       132.145.70.205
80/tcp                     ALLOW       Anywhere
443/tcp                    ALLOW       Anywhere
3443/tcp                   ALLOW       Anywhere
51820/udp                  ALLOW       Anywhere
```

Port `24740` is in the high ephemeral-safe range (`20000–29999`), was not bound by any TCP/UDP process, was not referenced in any `/etc/nginx`, `/etc/caddy`, or `/etc/systemd` configuration, and is **bound strictly to `127.0.0.1:24740`** (never `0.0.0.0` or `::`).

---

## 3. What Runs on the VPS vs. What Runs on the iPhone

### Hosted on the Ubuntu VPS (`/srv/prayer` behind Nginx on `https://prayer.xus.me`)
1. **`/` — Landing & iOS Install Page (`/srv/prayer/site/index.html`)**:
   - Overview of Prayer Clock Remote (WiFi + Bluetooth LE).
   - **"Open Web App"** button (`/app/`).
   - **iOS Native App section** with direct link to [BUILD_IOS.md](https://prayer.xus.me/download/BUILD_IOS.md), downloadable source bundle (`/download/prayer_clock_ios_src.tar.gz`), GitHub Actions / Codemagic CI artifacts info, and an inline SVG **QR Code** pointing to `https://prayer.xus.me/app/` for quick mobile access.
2. **`/app/` — Flutter Web Build (`/srv/prayer/app/build/web`)**:
   - Compiled Flutter Web fallback of the exact same codebase.
   - Displays a clear banner on iOS/browsers: *"Web version — Bluetooth is not available in browsers on iPhone; use the iOS app for Bluetooth."*
3. **`/download/` — Build Instructions & Artifacts (`/srv/prayer/download/`)**:
   - Hosts `BUILD_IOS.md`, `PARITY.md`, `DEPLOY.md`, `p4clock.html` (offline Web Bluetooth copy), and `prayer_clock_ios_src.tar.gz` (complete Flutter project ready for Xcode / CI signing).
4. **`/healthz` — Health Check Endpoint**:
   - Returns HTTP `200` with body `ok` when the local Dart/Python server process at `127.0.0.1:24740` is healthy.

### Runs on the iPhone (Native iOS Binary)
- The **Flutter iOS app** is a native iOS client compiled on macOS (either locally via Xcode on a Mac or via the included GitHub Actions `macos-latest` / Codemagic workflows in `.github/workflows/ios-release.yml` and `codemagic.yaml`) because Apple codesigning (`codesign` / Xcode toolchains) requires macOS and an Apple Developer certificate.
- Once installed on an iPhone (via Xcode direct install or TestFlight):
  - **Bluetooth LE** communicates directly from the iPhone's CoreBluetooth stack (`flutter_blue_plus`) to the P4 board's Nordic UART Service (`6e400001-b5a3-f393-e0a9-e50e24dcca9e`).
  - **WiFi / HTTP** communicates directly over the local LAN from the iPhone to `http://<board-ip>/api/...` using the scoped `NSAllowsLocalNetworking` ATS exception.

---

## 4. State Management Choice

- **Selected Package:** `provider` (`ChangeNotifier` + `ChangeNotifierProvider` / `Consumer`)
- **Rationale:**
  - Single, consistent reactive pattern across the entire codebase without code-generation build steps or mixed paradigms.
  - `ClockController` (`lib/state/clock_controller.dart`) owns the active `P4Transport` instance (`HttpTransport` or `BleTransport`), `connectionEpoch` cancellation token, live `/api/status` polling / BLE status stream subscription, `dirty` form flags (`pray`, `loc`, `set`), and mutual-exclusion transfer flags (`upBusy`, `dlBusy`, `fwBusy`).
  - All 8 tabs and overlays observe `ClockController` cleanly and never interact with HTTP or BLE APIs directly.

---

## 5. iOS App Transport Security (ATS), Permissions & Background Behavior

### Scoped ATS Exception (`NSAllowsLocalNetworking`)
In `ios/Runner/Info.plist`, cleartext HTTP is enabled **only** for local network traffic:
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```
- **Trade-off Note:** `NSAllowsLocalNetworking` allows plain `http://` connections to RFC 1918 private IPv4 addresses (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`), link-local addresses (`169.254.0.0/16`), and `.local` mDNS hostnames without triggering App Store review rejection (unlike blanket `NSAllowsArbitraryLoads = true`, which weakens security globally and requires justification to Apple Review).
- **Important Limitation:** If the Prayer Clock board is ever routed over a public/non-RFC1918 IP address (e.g., carrier-grade NAT `100.64.0.0/10`, public IP, or certain VPN subnets) over plain HTTP, iOS will block the cleartext request under `NSAllowsLocalNetworking`. In that scenario, either access the board on the local WiFi LAN or use Bluetooth LE.

### Required iOS Usage Strings in `ios/Runner/Info.plist`
1. `NSLocalNetworkUsageDescription`: `"Prayer Clock Remote uses your local WiFi network to connect to and control your Prayer Clock board."`
2. `NSBluetoothAlwaysUsageDescription`: `"Prayer Clock Remote uses Bluetooth Low Energy to connect to, configure, and transfer files with your Prayer Clock."`
3. `NSBluetoothPeripheralUsageDescription`: `"Prayer Clock Remote uses Bluetooth Low Energy to communicate with your Prayer Clock device."`
4. `NSLocationWhenInUseUsageDescription`: `"Used only when needed by system wireless APIs while managing your Prayer Clock connection."`

*(Note: `NSBonjourServices` is intentionally omitted because the app connects via direct IP/hostname or BLE GATT service UUID scan rather than active mDNS service browsing.)*

### Background Behavior & Local Notifications
- `UIBackgroundModes` for `bluetooth-central` is **not** enabled, matching App Store best practices for a remote-control utility where the hardware clock independently fires its own alarms and azan.
- `ClockController` listens to `AppLifecycleState` via `WidgetsBindingObserver`:
  - When the app transitions to `paused`/`inactive`, a prominent banner informs the user when resuming if the connection paused or dropped while backgrounded, and automatically refreshes `/api/status` (on WiFi) or triggers BLE auto-reconnect (`bleRetry(1..5)`).
- **Local Notifications (`flutter_local_notifications`)**:
  - When the app is running and receives a status transition into an active alarm (`src == 'alarm'`) or azan (`src == 'azan'`) with `test == false`, it requests iOS notification permission on-demand (never on app launch) and posts a local alert banner (`🔔 Alarm: <title>` or `🕌 Azan: <title>`).

---

## 6. Reverse Proxy & Systemd Configuration

### Nginx Vhost (`/etc/nginx/conf.d/prayer.xus.me.conf`)
Nginx is already running on the VPS serving other sites on ports 80 and 443. We added `/etc/nginx/conf.d/prayer.xus.me.conf` (and committed a copy at `/srv/prayer/deploy/prayer.xus.me.nginx.conf`) with a Let's Encrypt TLS certificate issued via Certbot for `prayer.xus.me`, proxying all traffic to `http://127.0.0.1:24740`.

### Systemd Service (`/etc/systemd/system/prayer.service`)
Runs `/srv/prayer/server.dart` (compiled native binary `/srv/prayer/prayer_server` bound to `127.0.0.1:24740`) under dedicated non-root system user `prayer`:
```ini
[Unit]
Description=Prayer Clock Web & Artifact Host (prayer.xus.me)
After=network.target

[Service]
Type=simple
User=prayer
Group=prayer
WorkingDirectory=/srv/prayer
Environment="PORT=24740"
Environment="HOST=127.0.0.1"
ExecStart=/srv/prayer/prayer_server
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
```
