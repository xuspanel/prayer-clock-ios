# Feature & UI Parity Matrix (`p4clock.html` → Flutter App)

This document maps every screen, tab, field, button, confirmation dialog, validation rule, API endpoint, and transport behavior from `p4clock.html` (2,147 lines) to the Flutter iOS & Web application located in `/srv/prayer/app`.

## 1. Global Header, Connection Card, PIN Overlay & Live Banners

| Web App Element / ID | Feature / Behavior | API / Transport | Flutter File & Widget | Status |
|---|---|---|---|---|
| `#heading` (`<h1>`) | Displays `☾ <bname>` (defaults to `☾ Prayer Clock`, updates from `settings.bname` via `nameSaved()`). | `/api/settings` | `lib/ui/home_shell.dart` (`AppHeader`) | Ported |
| `#conn` (`#cst`, `#fwv`) | Connection status indicator (`Not connected`, `Connecting Bluetooth...`, `Bluetooth: connected to <name> (MTU <mtu>)`, `Bluetooth lost - reconnecting...`, `WiFi: http://<ip>`) and firmware version string (`status.fw`). Also surfaces iOS app lifecycle background/disconnect state clearly. | `/api/hello`, `/api/status` | `lib/ui/widgets/connection_card.dart` (`ConnectionCard`) | Ported |
| `#bbtn`, `#bdis` | **Connect Bluetooth** / **Disconnect Bluetooth** buttons. Blocks if `upBusy \|\| dlBusy \|\| fwBusy` (`"Finish or cancel the transfer before changing connection"` / `"Finish or cancel the transfer before disconnecting"`). Requests BLE permission only when user taps **Connect Bluetooth**. | BLE GATT `6e400001-...` | `lib/ui/widgets/connection_card.dart` (`ConnectionCard`) | Ported |
| `#iprow` (`#ip`, `wifiIp()`) | Board IP/hostname input (`placeholder="WiFi: board IP or hostname"`) and **Connect WiFi** button. Validates `/^[A-Za-z0-9._:-]+$/` (`"Enter only the board IP address or hostname"`). Auto-fills from `/api/wifi` (`ipFill()`) when connected via BLE, caches IP in `shared_preferences` (`prefSet('ip', ip)`), with clear button/action. | `/api/wifi`, `/api/auth` | `lib/ui/widgets/connection_card.dart` (`ConnectionCard`) | Ported |
| `#iosw` (`#iosnote`, `#safari`) | Web-only helper when running on HTTPS/Bluefy trying to reach HTTP board (`Open in Safari` / copy HTTP URL). In native iOS app, direct HTTP works via scoped `NSAllowsLocalNetworking` ATS exception; on Flutter Web over HTTPS, offers direct link/copy fallback. | Local HTTP | `lib/ui/widgets/connection_card.dart` (`ConnectionCard`) | Ported |
| `#clock`, `#next` | Live clock bar (`clock • date • hijri • 🔋bat% • 📶 wifi` or `"Board clock not set"`) and next prayer indicator (`"Next: <next>"` in amber). | `/api/status` & BLE `"ev":"status"` | `lib/ui/home_shell.dart` (`StatusBanner`) | Ported |
| `#err` | Red error banner `"Board not reachable..."` shown when `/api/status` fails over WiFi. | `/api/status` | `lib/ui/home_shell.dart` (`StatusBanner`) | Ported |
| `#msg` | Sticky top message banner that auto-clears after 6,000 ms if unchanged, plus manual dismiss button. | Global UI state | `lib/ui/home_shell.dart` (`ToastBanner`) | Ported |
| `#alarm` (`#atitle`, `#snz`) | Active alarm / azan card (amber border) when `(src == 'alarm' \|\| src == 'azan') && !test`. Shows `🔔 Alarm: <title>` or `🕌 Azan: <title>`, **Snooze** button (`c('snooze')`, shown only when `src == 'alarm'`), and **■ Stop** button (`c('stop')`). Triggers foreground local notification via `flutter_local_notifications` when transitioning into active alarm/azan. | `/api/cmd` (`snooze`, `stop`) | `lib/ui/home_shell.dart` (`ActiveAlarmBanner`) | Ported |
| `#sn` (`#snt`) | Snoozed indicator card (`🔔 Snoozed until <snooze>`) when `snooze && !al`, with **Cancel snooze** button (`c('nosnooze')`). | `/api/cmd` (`nosnooze`) | `lib/ui/home_shell.dart` (`SnoozeBanner`) | Ported |
| `#login` (`#pin`, `#lmsg`) | Full-screen modal PIN lock overlay (`🔒 Enter PIN`, numeric password max 8 chars, **Unlock** and **Cancel** buttons). Triggered on HTTP 401 (`"Wrong PIN"` if PIN was non-empty) or 429 (`"Too many wrong PINs - wait 1 minute"`), or manual **Lock this page**. PIN is never persisted (`prefRemove('pin')` on startup). | `/api/auth` | `lib/ui/widgets/pin_overlay.dart` (`PinOverlay`) | Ported |

---

## 2. Tab 1: Remote (`#t-remote`)

| Web App Element / ID | Feature / Behavior | API / Transport | Flutter File & Widget | Status |
|---|---|---|---|---|
| `#title`, `#time`, `#fill` | Media player card showing current state (`Stopped`, `♫ <title>`, or `🔔 Test: <title>`), elapsed/duration `f(pos) / f(dur)` (`--:--` when `dur == 0`), and progress bar (`pos * 100 / dur`). | `/api/status` | `lib/ui/tabs/remote_tab.dart` (`RemoteTab`) | Ported |
| Transport buttons (`prev`, `#pp`, `stop`, `next`) | **⏮** (`c('prev')`), **▶ / ⏸** (`c('toggle')` depending on `d.playing`), **■** (`c('stop')`), **⏭** (`c('next')`). Requires `ready` (`"Unlock and connect first"`). | `/api/cmd` (`prev`, `toggle`, `stop`, `next`) | `lib/ui/tabs/remote_tab.dart` (`RemoteTab`) | Ported |
| `#vol`, `#vv` | Volume slider (`min="0"`, `max="21"`), 150 ms debounce (`c('vol', v)`), suppresses status overwrite for 1,500 ms while dragging (`Date.now() - drag > 1500`). | `/api/cmd` (`c: 'vol', v`) | `lib/ui/tabs/remote_tab.dart` (`RemoteTab`) | Ported |
| Playlist card (`#list`) | Header `♫ Playlist (/music)` with **📁 Folders** button (`openFilesTab('/music')`) and **↻** refresh button (`list()`). Displays tracks `1. <name>` with active track highlighted (`.on` when `i == cur`) and tap to play (`c('track', i)`). Shows `"No audio files in /music"` when empty. | `/api/list`, `/api/cmd` (`c: 'track', v: i`) | `lib/ui/tabs/remote_tab.dart` (`RemoteTab`) | Ported |

---

## 3. Tab 2: Prayer (`#t-pray`)

| Web App Element / ID | Feature / Behavior | API / Transport | Flutter File & Widget | Status |
|---|---|---|---|---|
| `#ptl`, `#phdr` | **Today** card: lists `Fajr`, `Sunrise`, `Dhuhr`, `Sunset`, `Maghrib` (`PN`) formatted via `hm(m)` (respecting 12h/24h setting `setD.h24`), highlighting `i == d.nexti`. Shows `"Prayer times not known yet (board clock not set)"` if `pt` is empty. `#phdr` shows `<city> | <method> | Fajr angle <angle> | Maghrib = sunset + <magh> min`. | `/api/status`, `/api/settings` | `lib/ui/tabs/prayer_tab.dart` (`PrayerTab`) | Ported |
| `#az0`, `#az1`, `#az2` | Checkboxes for `Azan Fajr`, `Azan Dhuhr`, `Azan Maghrib`. | `/api/settings` (`az0`, `az1`, `az2`) | `lib/ui/tabs/prayer_tab.dart` (`PrayerTab`) | Ported |
| `#azfajr`, `#azfile`, `#azmag` | Dropdown selects for `Fajr azan sound`, `Dhuhr azan sound`, `Maghrib azan sound` populated from `d.azfiles` via `fillAz()` (fallback `(no audio files in /azan)`). | `/api/settings` (`azfajr`, `azfile`, `azmag`) | `lib/ui/tabs/prayer_tab.dart` (`PrayerTab`) | Ported |
| `#azvol`, `#lead` | `Azan volume (0-21)` (`min=0, max=21`) and `Start azan early (0-500 s)` (`min=0, max=500`). | `/api/settings` (`azvol`, `lead`) | `lib/ui/tabs/prayer_tab.dart` (`PrayerTab`) | Ported |
| `#fdef`, `#fdefcb`, `#frow`, `#fangle` | `Fajr angle: method default (<def>)` checkbox; when unchecked, reveals `Custom Fajr angle (14.0 - 19.9)` decimal input (`#fangle`). Sends `fangle: 0` when checked, else `#fangle` value. | `/api/settings` (`fangle`) | `lib/ui/tabs/prayer_tab.dart` (`PrayerTab`) | Ported |
| `#magh`, `#azbg` | `Maghrib = sunset + min (0-30)` (`min=0, max=30`) and `Azan picture on the clock screen` checkbox (`#azbg`), plus explanatory text about `.bin` files in `/images`. | `/api/settings` (`magh`, `azbg`) | `lib/ui/tabs/prayer_tab.dart` (`PrayerTab`) | Ported |
| `azTest(0/1/2)`, `Stop`, `savePray()` | Buttons: **▶ Test Fajr**, **▶ Test Dhuhr**, **▶ Test Maghrib**, **■ Stop** (`c('stop')`), and **✔ Save prayer settings** (`POST /api/settings`). Preserves `dirty.pray` tracking so background status refreshes don't clobber edits. | `POST /api/azan/test`, `POST /api/settings` | `lib/ui/tabs/prayer_tab.dart` (`PrayerTab`) | Ported |

---

## 4. Tab 3: Alarms (`#t-alarms`)

| Web App Element / ID | Feature / Behavior | API / Transport | Flutter File & Widget | Status |
|---|---|---|---|---|
| `#acnt`, `#alist` | Shows `"Tap an alarm to edit it. <X> of <Y> alarms on."` Lists each alarm with enable/disable checkbox (`POST /api/alarm` `{i, on}`), bold time + label (`x.t   x.l`), and subtitle (`x.d`). Tapping opens editor card `#aed`. | `GET /api/alarms`, `POST /api/alarm` | `lib/ui/tabs/alarms_tab.dart` (`AlarmsTab`) | Ported |
| `#aed` (`#e_n`, `#e_lbl`, `#e_mode`) | **Edit alarm #<i+1>** card: `Title` (`maxlength="30"`, `placeholder="e.g. Suhoor"`), `When` selector (`-1`: Fixed time, `0`: Before / after Fajr, `1`: Before / after Dhuhr, `2`: Before / after Maghrib). | Local state / `/api/alarm` | `lib/ui/tabs/alarms_tab.dart` (`AlarmEditCard`) | Ported |
| `#e_fix` (`#e_time`) & `#e_rel` (`#e_dir`, `#e_off`, `#e_prev`) | Fixed time picker (`HH:MM`) when `mode == -1`. Relative mode (`mode >= 0`) shows `Before / after` (`-1` Before, `1` After), `Minutes (0-180)` (`0..180`), and live preview `#e_prev`: `"Today it rings at <hm> (<Prayer> is at <hm>)"` or `"This prayer time is not available"`. | Calculated from `lastSt.pt` | `lib/ui/tabs/alarms_tab.dart` (`AlarmEditCard`) | Ported |
| `#e_days`, `#e_ram`, `#e_dt`, `#e_daterow` (`#e_date`) | 7 day checkboxes (`Sun`..`Sat` bitmask `days |= 1 << d`). `Ramadan only (works with the days)` (`#e_ram`) and `Specific date (ignores days + Ramadan)` (`#e_dt`) are mutually exclusive. When `#e_dt` is checked, shows `Date` picker (`YYYY-MM-DD`, validates year 2000–2099: `"Alarm date must be between 2000 and 2099"` or `"Choose a date"`). | `POST /api/alarm` | `lib/ui/tabs/alarms_tab.dart` (`AlarmEditCard`) | Ported |
| `#e_snd`, `#e_vol`, `#e_vl` | `Sound (/alarms)` dropdown populated via `GET /api/fs/list?path=/alarms` filtered by `AUD` (`/\.(mp3\|m4a\|aac\|wav\|flac\|ogg)$/i`) with `"Default (alarm.mp3)"` (`""`). Volume slider `0..21` with live test volume update (`POST /api/alarm/test` `{a:'vol', vol}` after 150 ms when `lastSt.test` is true). | `GET /api/fs/list`, `POST /api/alarm/test` | `lib/ui/tabs/alarms_tab.dart` (`AlarmEditCard`) | Ported |
| `eTest()`, `eStop()`, `eSave()`, `eClose()`, `eDel()` | **▶ Test** (`{a:'play', path, vol}`), **■ Stop** (`{a:'stop'}`), **✔ Save** (`POST /api/alarm`), **Cancel** (stops test if active and hides editor), **🗑 Delete** (confirms `"Delete alarm <i+1>?"`, calls `POST /api/alarm` `{i, a:'del'}`). | `POST /api/alarm`, `POST /api/alarm/test` | `lib/ui/tabs/alarms_tab.dart` (`AlarmEditCard`) | Ported |

---

## 5. Tab 4: Location (`#t-loc`)

| Web App Element / ID | Feature / Behavior | API / Transport | Flutter File & Widget | Status |
|---|---|---|---|---|
| `#loc` | Current location summary: `"Now: <city>   <lat>, <lon>   |   <tz>"`. | `/api/settings` | `lib/ui/tabs/location_tab.dart` (`LocationTab`) | Ported |
| `#cq`, `clist()`, `geo()`, `#cmsg`, `#cres` | City search box (`placeholder="City name"`), **☰ List** button (`GET /api/cities?q=<cq>`), and **🌐 Online** button (`POST /api/geo/start` `{q}` followed by 1,000 ms polling of `GET /api/geo` until `state != 'busy'`). Offline list shows `<n>   <lat>, <lon>   <tz>` (tap to `useCity(n)`) and red **🗑** button (confirms `'Delete "<n>" from the cities list?'`, `POST /api/city` `{a:'del', name}`). Online results auto-select if `list.length == 1`, otherwise list choices (`POST /api/geo/use` `{i, name}`) plus `✕ Cancel` (`POST /api/geo/cancel`). | `/api/cities`, `/api/city`, `/api/geo/start`, `/api/geo`, `/api/geo/use`, `/api/geo/cancel` | `lib/ui/tabs/location_tab.dart` (`LocationTab`) | Ported |
| Manual entry (`#city`, `#lat`, `#lon`, `#tzsel`, `#tzrow`, `#tzval`, `#savecity`, `saveLoc()`) | `City name` (`maxlength=31`), `Latitude (South -)`, `Longitude (West -)`, `Time zone` dropdown (`TZS` + `Custom UTC offset` + `Custom POSIX rule`), conditional `#tzrow` (`UTC offset (e.g. +3, -5:30)` or `POSIX rule`), `Also save in the cities list` checkbox (default checked), and **✔ Save location** button (`POST /api/settings`). | `POST /api/settings` | `lib/ui/tabs/location_tab.dart` (`LocationTab`) | Ported |

---

## 6. Tab 5: Settings (`#t-set`)

| Web App Element / ID | Feature / Behavior | API / Transport | Flutter File & Widget | Status |
|---|---|---|---|---|
| `#bname`, `#namepreview`, `#namesaved` | `Clock name` (`maxlength=20`, `placeholder="P4-Clock"`). Validates `validClockName(n)` (`<=20` chars, `/^[A-Za-z0-9 _.-]+$/` and contains `[A-Za-z0-9]`, or empty). Live preview shows `Bluetooth: <ble>\nWiFi: http://<host>.local/` or validation warning. `#namesaved` shows `Saved Bluetooth name: <ble>\nSaved WiFi address: http://<host>.local/`. | `/api/settings` | `lib/ui/tabs/settings_tab.dart` (`SettingsTab`) | Ported |
| `#bright`, `#bv` | `Brightness` slider (`min=5, max=100`), 150 ms debounced live update `POST /api/settings` `{bright: v, live: 1}`. | `POST /api/settings` | `lib/ui/tabs/settings_tab.dart` (`SettingsTab`) | Ported |
| `#h24`, `#method`, `#hijri`, `#locksec` | `24-hour clock` checkbox, `Calculation method` dropdown (`<name>  (Fajr <angle>)`), `Hijri date adjust` dropdown (`-2 days` .. `+2 days`, `0 (Umm al-Qura)`), `Clock screen auto-lock (0-600 s, 0 = off)` (validates `/^\d+$/` and `<= 600`: `"Auto-lock must be 0 - 600 seconds"`). | `POST /api/settings` | `lib/ui/tabs/settings_tab.dart` (`SettingsTab`) | Ported |
| `#setsave` (`saveSet()`) | **✔ Save settings** button. Disables while saving (`setSaving`), posts `{bname, method, hijri, h24, locksec}`, displays contextual hostname/BLE scan hints on change. | `POST /api/settings` | `lib/ui/tabs/settings_tab.dart` (`SettingsTab`) | Ported |

---

## 7. Tab 6: WiFi (`#t-wifi`)

| Web App Element / ID | Feature / Behavior | API / Transport | Flutter File & Widget | Status |
|---|---|---|---|---|
| `#wst`, `#wrtc` | Displays multi-line WiFi status (`d.status`) and RTC sync note (`d.rtc`). Polls `GET /api/wifi` every 1,500 ms while `scan == 'busy'` or 4,000 ms while WiFi tab is active. | `GET /api/wifi` | `lib/ui/tabs/wifi_tab.dart` (`WifiTab`) | Ported |
| `#wcon`, `wfClear()`, `restart()`, `#wmaint` | **📶 Connect** / **✕ Disconnect** toggle (`wfToggle()`, confirms on WiFi before disconnecting: `'Disconnect WiFi? This page stops working (use Bluetooth).'`), **🗑 Clear saved** (`wfClear()`, confirms `'Erase the saved WiFi network and password?'`), **↻ Restart board** (`restart()`), and **🔧 OTA mode** (`maint()`, visible when `MODE == 'wifi'`). | `POST /api/wifi`, `POST /api/restart`, `POST /api/maint` | `lib/ui/tabs/wifi_tab.dart` (`WifiTab`) | Ported |
| `#wkeep` (`wfKeep()`) | `Stay connected (needed for the WiFi page + OTA)` checkbox. If unchecking while `keep0 && MODE == 'wifi'`, confirms `'With "Stay connected" OFF the board leaves WiFi after the time sync and this page stops working. Continue?'` and reverts checkbox if cancelled. | `POST /api/wifi` `{a:'keep', v}` | `lib/ui/tabs/wifi_tab.dart` (`WifiTab`) | Ported |
| `#wscan`, `#wl`, `#wssid`, `#wpass`, `wfJoin()` | **↻ Scan** button (`POST /api/wifi` `{a:'scan'}`), scanned network list `📶 <ssid>   (<rssi> dBm)  [open]` (tapping fills `#wssid`, clears `#wpass`, focuses password), `Network` input, `Password` input, `Show password` toggle, and **✔ Join network** button (validates non-empty SSID `"Choose a network first"`, confirms if `MODE == 'wifi'`, posts `{a:'join', ssid, pass}`). | `POST /api/wifi` | `lib/ui/tabs/wifi_tab.dart` (`WifiTab`) | Ported |

---

## 8. Tab 7: Files (`#t-files`)

| Web App Element / ID | Feature / Behavior | API / Transport | Flutter File & Widget | Status |
|---|---|---|---|---|
| `#fbar` (`Up`, `↻`, `+ Folder`, `⬆ Upload files`, `#paste`, `#upc`) | Action toolbar: **⬆ Up** (`fsl(up(cwd))`), **↻** (`fsl(cwd); fsinfo()`), **+ Folder** (prompts for folder name, validates `validFileName(n)` no slashes/control chars, posts `/api/fs/mkdir`), **⬆ Upload files** (multi-file picker via `file_picker`), **Paste** (`#paste`, shown when clipboard has copy/cut item), **Cancel** (`#upc`, shown during active upload/download). | `/api/fs/list`, `/api/fs/info`, `/api/fs/mkdir`, `/api/fs/copy`, `/api/fs/move` | `lib/ui/tabs/files_tab.dart` (`FilesTab`) | Ported |
| `#cwd`, `#space` | Current directory path and free space summary `(<free> free of <total>)`. Warns `"Big folder - only the first part is shown"` if `d.more` is true. | `/api/fs/list`, `/api/fs/info` | `lib/ui/tabs/files_tab.dart` (`FilesTab`) | Ported |
| `#sel` (`#seln`, `#bplay`, `#bdl`, `Copy`, `Cut`, `Rename`, `Delete`, `✕`) | Selected file/folder bar: **▶ Play** (`POST /api/fs/play`, shown for non-dir audio files matching `AUD`), **⬇ Download** (`fdl()`, shown for files), **Copy** (`clipSet(0)`), **Cut** (`clipSet(1)`), **Rename** (`fren()` dialog with validation, `POST /api/fs/move`), **Delete** (`fdel()` confirmation dialog `"Delete <sel> and EVERYTHING inside it?"`, `POST /api/fs/delete`), **✕** deselect. | `/api/fs/play`, `/api/fs/move`, `/api/fs/delete` | `lib/ui/tabs/files_tab.dart` (`FilesTab`) | Ported |
| `#fl` | Directory listing sorted case-insensitively: `📁 ..` (when `cwd != '/'`), `📁 <dir>` (tap opens folder, `⋯` button selects directory), `📄 <file> (<size>)` (tap selects file, `⬇` button downloads immediately). Shows `(empty folder)` when empty. | `/api/fs/list` | `lib/ui/tabs/files_tab.dart` (`FilesTab`) | Ported |
| File Download (`fdlPath`, `bleDownload`) | Mutual exclusion via `dlBusy`/`upBusy`/`fwBusy`. Over BLE: confirms if `> 1 MB` (`"Bluetooth transfer speed varies. Download <sz> over Bluetooth?"`), reads chunks via `GET /api/fs/read?path=<p>&off=<off>` (base64 `d.b64`, `d.size`, `d.eof`), displays percentage and KB/s, supports Cancel (`upStop`). Over WiFi: fetches `GET /api/fs/get?pin=<P>&path=<p>` with progress. On iOS/mobile, saves temp file and opens native iOS Share / Save to Files sheet (`share_plus`); on web, triggers browser download. | `GET /api/fs/read` (BLE), `GET /api/fs/get` (WiFi) | `lib/ui/tabs/files_tab.dart` & `lib/services/transfer_controller.dart` | Ported |
| File Upload (`upl`, `webUpload`, `bleUpload`) | Supports multiple files sequentially with progress (`Uploading <name> <pct>% (<kb> KB/s, <i> of <n>)`) and Cancel (`upCancel()`). Over WiFi: calls `POST /api/fs/upbegin` `{dir, name}`, then streams raw `application/octet-stream` body to `POST /api/fs/put`. Over BLE: confirms if total `> 1 MB`, calls `POST /api/fs/up` with `{a:'begin', dir, name}`, chunks of `3072` bytes as base64 `{a:'data', off, b64}`, `{a:'end'}`, and sends `{a:'abort'}` in `finally` if interrupted before `end`. | `/api/fs/upbegin` + `/api/fs/put` (WiFi), `/api/fs/up` (BLE) | `lib/ui/tabs/files_tab.dart` & `lib/services/transfer_controller.dart` | Ported |

---

## 9. Tab 8: System (`#t-sys`)

| Web App Element / ID | Feature / Behavior | API / Transport | Flutter File & Widget | Status |
|---|---|---|---|---|
| `#np`, `setPin()` | `New PIN (4-8 digits, empty = no PIN)` input and **Set PIN** button. Validates `/^\d{4,8}$/` if non-empty (`"PIN must be 4 - 8 digits, or empty to remove it"`). Confirms if empty (`"Remove the PIN? Anyone nearby / on your WiFi can then use this page."`). Updates active session PIN `P = d.pin` on success. | `POST /api/settings` `{newpin}` | `lib/ui/tabs/system_tab.dart` (`SystemTab`) | Ported |
| `setTime()` | **🕒 Set board clock from this phone** button (`POST /api/time` `{t: floor(now/1000)}`). Displays `"Board clock set"` or `"Clock set, but the RTC chip was not written"`. | `POST /api/time` | `lib/ui/tabs/system_tab.dart` (`SystemTab`) | Ported |
| `logout()`, `restart()` | **Lock this page** button (blocks if transfer busy: `"Finish or cancel the transfer before locking this page"`, clears `P` and opens PIN modal) and **↻ Restart board** button (confirms `"Restart the board now?"`, posts `/api/restart`). | `POST /api/restart` | `lib/ui/tabs/system_tab.dart` (`SystemTab`) | Ported |
| `#otacard` (`#fw`, `ota()`, `#otas`, `#dlpage`) | **⬆ Firmware update (OTA, WiFi only)** card (visible when `MODE == 'wifi'`). Selects `.bin` file, validates `/\.bin$/i` (`"That is not a .bin file"`), confirms `"Install <name>? The clock restarts when done."`, uploads multipart `firmware` field to `POST /api/ota?pin=<P>` with live progress `"Uploading <pct>% - do not close this page"`. Also includes **Offline Bluetooth page** section with **⬇ Download p4clock.html** button (`BASE + '/p4clock.html'`). | `POST /api/ota` | `lib/ui/tabs/system_tab.dart` (`SystemTab`) | Ported |
| `#mtcard` (`#mtbtn`, `maint()`, `#mts`) | **🔧 Maintenance mode (WiFi only)** card (visible when `MODE == 'wifi'`). Confirms `"Restart the clock in maintenance mode?\nThe clock, alarms and azan pause until you restart it normally from the maintenance page."`, calls `POST /api/maint`, runs 20-second countdown (`"Restarting in maintenance mode... the maintenance page opens in <s> s"`), and opens board URL `http://<ip>/`. | `POST /api/maint` | `lib/ui/tabs/system_tab.dart` (`SystemTab`) | Ported |
| `#vdcard` (`#vdbtn`, `vmode()`, `#vds`) | **🎥 Video mode** card. Confirms `"Restart the clock in video mode?\nIt goes back to the clock by itself before the next azan or alarm."`, calls `POST /api/video`, shows `"Restarting in video mode..."` (with 20s redirect on WiFi or screen note on BLE). | `POST /api/video` | `lib/ui/tabs/system_tab.dart` (`SystemTab`) | Ported |
| `#concard` (`#bcmd`, `conSend()`, `#blelog`) | **🖥 Bluetooth console** card (visible when `MODE == 'ble'`). Sends raw newline-delimited text commands over BLE RX characteristic (redacting `pin <secret>` as `>> pin [hidden]` in `#blelog`), displays incoming non-JSON or unrouted lines as `<< <line>` (retaining up to 300 lines), and **Clear** button. Blocks during transfers (`"Wait for the Bluetooth transfer to finish"`). | Raw BLE RX/TX | `lib/ui/tabs/system_tab.dart` (`SystemTab`) | Ported |

---

## 10. Transport & Protocol Parity

| Protocol Aspect | Web App Specification (`p4clock.html`) | Flutter Implementation | Status |
|---|---|---|---|
| Transport interface | Shared `api(p, a, post)` with `connectionEpoch` cancellation and HTTP 401/429 interception. | `abstract class P4Transport` (`lib/transport/p4_transport.dart`) implemented by `HttpTransport` and `BleTransport`. | Ported |
| BLE GATT UUIDs | Service `6e400001-b5a3-f393-e0a9-e50e24dcca9e`, RX `6e400002-...`, TX `6e400003-...`. | `BleTransport` (`lib/transport/ble_transport.dart`) using `flutter_blue_plus`. | Ported |
| BLE Framing & Chunking | Request `{"id":<n>,"p":"<path>","m":0\|1,"a":{...}}\n` (all values in `a` coerced to `String`, including `pin`). Chunk size `Math.max(20, Math.min(240, mtu - 3))` negotiated via `/api/hello`. Incoming buffer max 262,144 bytes, newline-delimited, strips trailing `\r`, routes `{"id":...}` to pending request, `{"ev":"status","d":{...}}` to `statusStream`, and non-JSON/unmatched lines to `consoleStream`. | `BleLineFramer` & `BleChunker` (`lib/transport/ble_framing.dart`) + `BleTransport` (`lib/transport/ble_transport.dart`). | Ported |
| BLE Auto-Reconnect | Up to 5 automatic reconnect attempts at 2,000 ms intervals (`bleRetry(1..5)`) upon unexpected disconnect (`!bManual`). | `BleTransport` auto-reconnect loop (`lib/transport/ble_transport.dart`). | Ported |
| WiFi HTTP Transport | `GET <BASE><p>?<URLSearchParams(a)>` or `POST <BASE><p>` with `application/x-www-form-urlencoded` body `URLSearchParams(a)`, `cache: no-store`. Polls `/api/status` every 1,000 ms when idle. | `HttpTransport` (`lib/transport/http_transport.dart`). | Ported |
| Omissions | None. Every tab, field, endpoint, validation, confirmation dialog, and transfer mode from `p4clock.html` is ported 1:1. | — | 0 Omissions |
