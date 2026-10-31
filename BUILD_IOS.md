# Building, Signing & Deploying the Prayer Clock iOS App (`BUILD_IOS.md`)

Because Apple's iOS SDK, `xcodebuild`, and `codesign` toolchains run exclusively on macOS, the Linux VPS (`prayer.xus.me`) verifies the Dart code (`flutter analyze`, `flutter test`), compiles the Flutter Web fallback (`/app/`), and packages the complete Flutter source project (`/download/prayer_clock_ios_src.tar.gz`).

Follow either **Option A (Local Mac + Xcode)** or **Option B (GitHub Actions / Codemagic macOS CI Runner)** below to produce a signed `.ipa` for a physical iPhone or TestFlight.

---

## 1. Pre-Configured iOS Settings in This Repo

All required iOS configuration has already been applied to `ios/Runner/`:

- **Bundle Identifier:** `me.xus.prayerclock` (configured in `ios/Runner.xcodeproj/project.pbxproj`)
- **Display Name:** `Prayer Clock` (`CFBundleDisplayName` in `ios/Runner/Info.plist`)
- **Minimum iOS Deployment Target:** `iOS 13.0` (compatible with `flutter_blue_plus`, `flutter_local_notifications`, and `share_plus`)
- **App Transport Security (`ios/Runner/Info.plist`):**
  - `NSAppTransportSecurity` → `NSAllowsLocalNetworking = true` (allows plain HTTP to local LAN IPs `192.168.x.x`, `10.x.x.x`, `172.16-31.x.x`, and `.local` mDNS hostnames without global `NSAllowsArbitraryLoads`).
- **Privacy Usage Descriptions (`ios/Runner/Info.plist`):**
  - `NSLocalNetworkUsageDescription`: *"Prayer Clock Remote uses your local WiFi network to connect to and control your Prayer Clock board."*
  - `NSBluetoothAlwaysUsageDescription`: *"Prayer Clock Remote uses Bluetooth Low Energy to connect to, configure, and transfer files with your Prayer Clock."*
  - `NSBluetoothPeripheralUsageDescription`: *"Prayer Clock Remote uses Bluetooth Low Energy to communicate with your Prayer Clock device."*
  - `NSLocationWhenInUseUsageDescription`: *"Used only when needed by system wireless APIs while managing your Prayer Clock connection."*

---

## 2. Option A: Build & Install on a Real iPhone via a Mac (Xcode)

### Step 1: Download the Project onto Your Mac
```bash
curl -fL https://prayer.xus.me/download/prayer_clock_ios_src.tar.gz -o prayer_clock_ios_src.tar.gz
mkdir -p prayer_clock && tar -xzf prayer_clock_ios_src.tar.gz -C prayer_clock
cd prayer_clock
```

### Step 2: Fetch Flutter Packages & CocoaPods
```bash
flutter pub get
cd ios && pod install && cd ..
```

### Step 3: Configure Signing in Xcode
1. Open the workspace in Xcode:
   ```bash
   open ios/Runner.xcworkspace
   ```
2. In the left navigator, select **Runner** (top-level project) → **Targets: Runner** → **Signing & Capabilities**.
3. Check **Automatically manage signing**.
4. Select your **Team** (your Apple Developer Account or Personal Team).
5. If using a free Personal Team and `me.xus.prayerclock` is already registered, change **Bundle Identifier** to a unique value (e.g. `me.xus.prayerclock.<yourinitials>`).
6. **Capabilities check:**
   - CoreBluetooth in foreground mode does **not** require enabling `Background Modes` (`bluetooth-central`). Leave `Background Modes` off unless you intend to justify persistent background BLE polling to App Review.
   - Verify `ios/Runner/Info.plist` contains the four `NS*UsageDescription` keys and `NSAppTransportSecurity` → `NSAllowsLocalNetworking = true` (already committed).

### Step 4: Run Directly on a Connected iPhone
1. Plug your iPhone into your Mac via USB, unlock the iPhone, and tap **Trust This Computer**.
2. On iOS 16+, enable **Developer Mode** on the iPhone under **Settings → Privacy & Security → Developer Mode**.
3. Run from terminal:
   ```bash
   flutter run --release -d <your-iphone-device-id>
   ```
   *(Run `flutter devices` to see your iPhone's device ID.)*

### Step 5: Produce a Signed `.ipa` for TestFlight / App Store Connect
1. Ensure your Apple Distribution certificate and App Store provisioning profile for `me.xus.prayerclock` are installed in Xcode.
2. Build the release archive and `.ipa`:
   ```bash
   flutter build ipa --release \
     --build-name=1.0.0 \
     --build-number=1
   ```
3. The signed `.ipa` is written to:
   ```text
   build/ios/ipa/prayer_clock.ipa
   ```
4. Upload to TestFlight using either:
   - **Xcode Organizer:** Open `build/ios/archive/Runner.xcarchive` in Xcode (`open build/ios/archive/Runner.xcarchive`) and click **Distribute App → TestFlight & App Store**.
   - **Command Line (`xcrun altool`):**
     ```bash
     xcrun altool --upload-app --type ios \
       -f build/ios/ipa/prayer_clock.ipa \
       --apiKey "$APP_STORE_CONNECT_API_KEY_ID" \
       --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"
     ```

---

## 3. Option B: Automated Cloud Build without a Local Mac (GitHub Actions / Codemagic)

Two ready-to-run macOS CI workflows are included in the project root:

### 1. GitHub Actions (`.github/workflows/ios-release.yml`)
Runs on `macos-latest`:
1. Push the project directory (`/srv/prayer/app`) to a GitHub repository.
2. For an **unsigned `.ipa` artifact** (for inspection or external signing with AltStore / SideStore / Sideloadly / `ldid`), simply trigger the workflow from the **Actions** tab (`workflow_dispatch`) with no secrets required — it uploads `prayer-clock-unsigned-ipa` to the workflow run artifacts.
3. For a **signed TestFlight `.ipa`**, add the following repository secrets in GitHub (**Settings → Secrets and variables → Actions**):
   - `BUILD_CERTIFICATE_BASE64`: Base64-encoded `.p12` Apple Distribution certificate
   - `P12_PASSWORD`: Password for the `.p12` file
   - `BUILD_PROVISION_PROFILE_BASE64`: Base64-encoded `.mobileprovision` App Store profile
   - `KEYCHAIN_PASSWORD`: Temporary password for the runner keychain
   - `APP_STORE_CONNECT_ISSUER_ID`: App Store Connect API Issuer ID
   - `APP_STORE_CONNECT_KEY_ID`: App Store Connect API Key ID
   - `APP_STORE_CONNECT_PRIVATE_KEY`: Contents of `AuthKey_<KEY_ID>.p8`

### 2. Codemagic (`codemagic.yaml`)
1. Connect your repository to [Codemagic](https://codemagic.io).
2. Configure Automatic Code Signing under **Team Settings → Apple Developer Portal integration**.
3. Start a build using the `ios-release` workflow in `codemagic.yaml`. Codemagic will compile the app on a macOS M2 runner, sign the `.ipa`, and publish it directly to **TestFlight**.
