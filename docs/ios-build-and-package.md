# iOS Build & Package

This page covers the full lifecycle of shipping `retold-remote-ios`: building locally, debugging in the Simulator and on a device, distributing via TestFlight, and submitting to the App Store.

## Prerequisites

- macOS 14 Sonoma or later
- Xcode 15 or later
- An active **Apple Developer Program** membership ($99/yr) — required for device, TestFlight, and App Store.
- An App Store Connect account with access to the app record.
- A valid **Bundle Identifier**, e.g. `com.yourorg.retoldremote`.
- Command-line tools: `xcode-select --install`

## 1. Project Layout at a Glance

```
retold-remote-ios/
├── RetoldRemote.xcodeproj
├── RetoldRemote/
│   ├── Configuration/
│   │   ├── Debug.xcconfig
│   │   ├── Release.xcconfig
│   │   └── Local.xcconfig.sample
│   ├── Resources/Info.plist
│   └── ...
├── RetoldRemoteTests/
├── RetoldRemoteUITests/
├── fastlane/           (optional)
└── scripts/
    ├── bump-version.sh
    └── archive.sh
```

## 2. Schemes and Configurations

Three schemes ship with the project:

| Scheme | Configuration | Server |
|---|---|---|
| `RetoldRemote-Dev` | Debug | local or staging |
| `RetoldRemote-Staging` | Release | staging |
| `RetoldRemote` | Release | production |

Each scheme links a different `.xcconfig`, which sets `RETOLD_REMOTE_BASE_URL`, the app display name, and the bundle ID suffix so all three can coexist on a device.

## 3. Debugging in the Simulator

The fast inner loop.

1. Select a scheme (usually `RetoldRemote-Dev`).
2. Choose an iPhone 15 or iPad Pro simulator from the device menu.
3. Press **⌘R** to build and run.
4. Set breakpoints in Xcode as usual. The debugger attaches automatically.

### Useful Simulator Tricks

- **Network conditioning** — `xcrun simctl status_bar <device> override --dataNetwork none` to simulate offline.
- **Location** — `Features → Location` menu to test location-aware flows.
- **Push notifications** — drop an APNs `.apns` payload file onto the Simulator window to deliver a local push without APNs.
- **Keychain reset** — `xcrun simctl erase <device>` to wipe saved credentials.
- **Deep links** — `xcrun simctl openurl booted "retoldremote://records/42"`.

### Inspecting Network Traffic

Use Apple's **Instruments → Network** template, or run against a local `mitmproxy` by setting `HTTP_PROXY` in the Simulator's Wi-Fi settings. For TLS interception, install the mitmproxy CA via `Settings → General → About → Certificate Trust Settings`.

## 4. Debugging on a Physical Device

Required for: push notifications (real APNs), camera, biometrics, background uploads, performance profiling.

### One-time device setup

1. Plug the iPhone/iPad into your Mac with a cable (or pair wirelessly from `Window → Devices and Simulators`).
2. On the device: **Settings → Privacy & Security → Developer Mode → On**, then reboot.
3. In Xcode, open **Settings → Accounts** and add your Apple ID.
4. Select the `RetoldRemote` target → **Signing & Capabilities** → pick your **Team**.
5. Let Xcode auto-manage signing; it will create a development certificate and provisioning profile.

### Run on device

1. Select your device from the device menu.
2. Press **⌘R**.
3. The first time, the device will prompt you to trust the developer certificate: **Settings → General → VPN & Device Management → Developer App → Trust**.

### Wireless debugging

Once paired over USB, check **Connect via network** in `Window → Devices and Simulators`. You can unplug and continue debugging over Wi-Fi as long as the Mac and device are on the same network.

### Capturing logs from a device

```bash
# Stream system logs filtered to the app
log stream --device --predicate 'subsystem == "com.yourorg.retoldremote"'

# Or grab a sysdiagnose bundle
sudo log collect --device --output retold-remote.logarchive
```

## 5. Archiving a Release Build

An archive is a signed, symbolicated `.xcarchive` — the artifact that gets uploaded to App Store Connect.

### From Xcode

1. Select the `RetoldRemote` scheme and set the destination to **Any iOS Device (arm64)**.
2. **Product → Archive**. Xcode builds a Release configuration and opens the **Organizer**.
3. In the Organizer, select the new archive and click **Distribute App**.

### From the command line

```bash
# 1. Bump version and build number
./scripts/bump-version.sh 1.2.0

# 2. Archive
xcodebuild \
  -project RetoldRemote.xcodeproj \
  -scheme RetoldRemote \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/RetoldRemote.xcarchive \
  clean archive

# 3. Export an IPA using a signing export options plist
xcodebuild \
  -exportArchive \
  -archivePath build/RetoldRemote.xcarchive \
  -exportPath build/ipa \
  -exportOptionsPlist scripts/ExportOptions.plist
```

A minimal `ExportOptions.plist` for App Store distribution:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>method</key><string>app-store</string>
  <key>teamID</key><string>YOURTEAMID</string>
  <key>uploadSymbols</key><true/>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
```

## 6. TestFlight

TestFlight is Apple's beta distribution channel. Up to 10,000 external testers, 90-day build lifetime.

### Upload a build

From Xcode Organizer: **Distribute App → App Store Connect → Upload**. Or via CLI:

```bash
xcrun altool --upload-app \
  --type ios \
  --file build/ipa/RetoldRemote.ipa \
  --apiKey YOUR_KEY_ID \
  --apiIssuer YOUR_ISSUER_ID
```

(Generate App Store Connect API keys under **Users and Access → Keys**. Store the `.p8` file in `~/.appstoreconnect/private_keys/`.)

### After upload

1. Wait 5–30 minutes for Apple to process the build. You will receive an email when it is ready.
2. In **App Store Connect → My Apps → RetoldRemote → TestFlight**, the build appears under **iOS Builds**.
3. Provide **Export Compliance** answers. If you use only standard HTTPS, you can declare the build exempt.
4. Add **What to Test** notes.
5. Assign the build to an internal tester group (up to 100 testers, immediate access) or an external group (requires Beta App Review, typically < 24 hours for updates).
6. Testers install the TestFlight app from the App Store, accept the invite, and install the build.

### Fastlane shortcut

If you use fastlane, the whole flow collapses to:

```bash
bundle exec fastlane beta
```

where the `beta` lane calls `build_app`, `upload_to_testflight`, and optionally `slack` to notify the team.

## 7. App Store Submission

1. In **App Store Connect → My Apps → RetoldRemote → App Store**, create a new version (e.g. `1.2.0`).
2. Fill in metadata:
   - What's New in This Version
   - Screenshots — at minimum: 6.7" iPhone, 6.1" iPhone, 12.9" iPad. Use `fastlane snapshot` to automate.
   - Keywords, subtitle, promotional text
   - App Privacy — declare data collection per Apple's privacy nutrition label format. `retold-remote-ios` collects: account info, diagnostic data, and (if used) photos. All linked to the user, none used for tracking.
3. Under **Build**, select the TestFlight build you want to ship.
4. Set **App Review Information** — demo account credentials for a `retold-remote` test server, contact email, and notes explaining the app's purpose (especially that it is a client for a private server).
5. Choose **Version Release**: manual or automatic on approval.
6. Click **Add for Review**, then **Submit for Review**.

Review typically takes 24–48 hours. Common rejection reasons for this kind of app:

- **Missing demo account** — reviewers must be able to sign in.
- **Crash on launch** — test the Release build on a real device first.
- **Unused permissions** — remove any `NS*UsageDescription` keys you do not actually use.
- **Minimum functionality** — make sure the app does something useful without requiring the reviewer to set up their own server; ship a default demo server URL if possible.

## 8. Post-Release

- **Crashes** — Xcode Organizer → **Crashes** tab pulls symbolicated reports from App Store Connect. Ensure `uploadSymbols` is true in your export options so dSYMs are uploaded.
- **Metrics** — Organizer → **Metrics** shows launch times, hangs, disk writes, and energy.
- **Staged rollout** — when releasing a new version, enable **Phased Release for Automatic Updates** to ramp over 7 days.
- **Hotfixes** — for urgent fixes, use **Expedited Review** sparingly. Apple grants one or two per year per app.

## 9. Troubleshooting

| Problem | Fix |
|---|---|
| `No signing certificate "iOS Development" found` | Xcode → Settings → Accounts → Download Manual Profiles, or enable automatic signing. |
| `Unable to install: The executable was signed with invalid entitlements` | The provisioning profile is missing a capability you enabled. Regenerate it in the Developer portal. |
| TestFlight build stuck "Processing" for hours | Usually a dSYM or ITMS issue — check email from Apple for details. |
| Push notifications silent in Release but work in Debug | You uploaded a dev APNs token, or the app is not using the `aps-environment: production` entitlement. |
| `ITMS-90683: Missing Purpose String` | Add the required `NS*UsageDescription` key to `Info.plist`. |
| Archive builds but Organizer shows "Other Items" instead of "iOS Apps" | Scheme's archive product type is wrong — make sure it is building the app target, not a framework. |

## 10. Reference Commands

```bash
# List available simulators
xcrun simctl list devices available

# Boot a specific simulator
xcrun simctl boot "iPhone 15"

# Install a built .app on a booted simulator
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/RetoldRemote.app

# Open a deep link on a booted simulator
xcrun simctl openurl booted "retoldremote://home"

# Build number bump
agvtool next-version -all

# Marketing version bump
agvtool new-marketing-version 1.2.0
```
