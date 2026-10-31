---
name: iphone-device-build
description: "Build, sign, install, and launch the native VocabularyWidget app on the user's physical iPhone. Use when asked to run this app on iPhone or install an iOS demo. Not for the Unity game, Simulator-only testing, TestFlight, or App Store distribution."
---

# Build and run VocabularyWidget on an iPhone

## Project

- Native SwiftUI app and WidgetKit extension: `VocabularyWidget.xcodeproj`
- App scheme: `VocabularyWidgetApp`
- Host target: `VocabularyWidgetApp`; extension target: `VocabularyWidgetExtension`
- Minimum iOS version: 17.0
- This is separate from the Unity `WordShooter` project.

## 1. Preflight

1. Read the current request and preserve all existing source and user data. Check `git status --short` if this project is inside a Git repository; this folder was not a Git repository at the last check.
2. Verify Xcode and the currently paired device:

   ```bash
   xcode-select -p
   security find-identity -v -p codesigning
   xcrun devicectl list devices
   ```

3. Verify the Apple Development team, signing identity, device name/UDID, app bundle identifier, and App Group before using them. Do not infer that the Unity game's signing setup automatically applies to this app.
4. Use a fresh build directory outside the source tree. Do not remove previous builds or erase app data.

### Last observed configuration (verify before reuse)

- The project still has placeholder bundle identifiers `com.example.VocabularyWidget` and `com.example.VocabularyWidget.WidgetKit`.
- The App Group `group.com.example.VocabularyWidget` is also a placeholder and is present in both entitlement files and `Shared/WidgetProgressStore.swift`.
- A physical-device build needs a unique app bundle identifier and an App Group registered for the selected Apple Developer team. Update the host and extension identifiers, both entitlements, and the shared store consistently before signing.
- The user-provided WordShooter build notes listed team `PD2729ZJNT` and an iPhone 17 Pro Max UDID `00008150-000215C11E12401C`. These details were not verified for VocabularyWidget in the last run; check the connected Xcode account and device list before using them.
- On 2026-10-30, `security find-identity -v -p codesigning` returned **0 valid identities**. `xcrun devicectl list devices` and a direct `devicectl device info details` query for the user-provided iPhone UDID both timed out while starting CoreDeviceService; `xcdevice list` showed only My Mac. Repeat preflight on the next attempt; do not report installation based on the earlier unsigned build.

## 2. Build and sign

Choose identifiers already available to the user's team, update the project/entitlements as needed, and confirm the configured Apple Development identity before invoking provisioning. Automatic provisioning may contact Apple's services. Do not create a new Apple account, switch teams, or reuse the Unity app's bundle identifier.

From the `VocabularyWidget` directory, create and record a unique output directory:

```bash
set -e
BUILD_ROOT="/private/tmp/VocabularyWidgetBuilds"
mkdir -p "$BUILD_ROOT"
VW_BUILD="$(mktemp -d "$BUILD_ROOT/iphone-$(date +%Y%m%d-%H%M%S)-XXXXXX")"
printf 'Build directory: %s\n' "$VW_BUILD"
```

After replacing `TEAM_ID` with the verified team, build the signed device app:

```bash
xcodebuild -project VocabularyWidget.xcodeproj \
  -scheme VocabularyWidgetApp -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$VW_BUILD/derived-data" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=TEAM_ID \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  build > "$VW_BUILD/xcodebuild.log" 2>&1
```

Require exit code 0 and `** BUILD SUCCEEDED **`. If it fails, inspect focused error excerpts from the log. Find the host `.app` under `derived-data/Build/Products/Release-iphoneos`; verify its signature, bundle identifier, team, and App Group entitlements before installing.

## 3. Install and launch

Use the verified device UDID and the actual host `.app` path:

```bash
xcrun devicectl list devices
xcrun devicectl device install app --device DEVICE_UDID "/absolute/path/to/VocabularyWidgetApp.app"
xcrun devicectl device process launch --device DEVICE_UDID APP_BUNDLE_ID
```

Run installation and launch as separate steps; launch only after installation succeeds. Do not uninstall the existing app or reset its App Group data. A successful app launch does not automatically add the widget to the Home Screen: open the widget gallery on the iPhone and add **Từ vựng mỗi ngày** if it is not already there.

If the device is unavailable, report the exact `devicectl` result and ask the user to unlock/trust the iPhone, enable Developer Mode if needed, or reconnect it by USB. Do not claim the app is on the phone unless installation and launch both succeed.

## 4. Finish

- Keep the successful signed build and logs available; report their exact locations.
- Report build, signing, installation, and launch as separate outcomes.
- Ask the user to check the app's topic list and the widget's word, Vietnamese meaning, part of speech, and example on the phone.
- Do not commit, push, upload, or start TestFlight/App Store distribution unless requested.
