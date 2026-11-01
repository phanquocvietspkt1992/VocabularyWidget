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

1. Read the current request and preserve all existing source and user data. Check `git status --short` and preserve unrelated worktree changes.
2. Verify Xcode and the currently paired device:

   ```bash
   xcode-select -p
   security find-identity -v -p codesigning
   xcrun devicectl list devices
   ```

3. Verify the Apple Development team, signing identity, device name/UDID, app bundle identifier, and App Group before using them. Do not infer that the Unity game's signing setup automatically applies to this app.
4. Use a fresh build directory outside the source tree. Do not remove previous builds or erase app data.

### Deployment version preparation

- Verify the Mac's local date with `date '+%Y.%m.%-d %Z'` before preparing an authorized deployment. Use `MARKETING_VERSION=yyyy.M.d` (three numeric components) and `CURRENT_PROJECT_VERSION=N` in all four host/extension Debug/Release target configurations. Do not use a four-part iOS marketing version.
- The app derives its `dd.MM.yyyy.N` footer only from `Bundle.main`'s `CFBundleShortVersionString` and `CFBundleVersion`; do not add a separate date literal, runtime clock, or runtime counter.
- Determine N from the last evidenced successful physical-iPhone installation AND launch: the next deployment on that same local day increments N by one; a new local day starts at 1. Verify the deployed metadata and success logs, not just the current source settings. If that evidence is missing or ambiguous, resolve it before choosing a counter.
- Preparing or compiling a build does not consume N. Failed build/install/launch attempts retain the pending N for same-day retries; only a successful installation plus launch consumes it. If the local day changes before retrying, prepare the new date with N=1.
- This source is already prepared for `2026.11.1` / `2` (`01.11.2026.2`). Do not automatically bump 2 to 3 before its first successful authorized installation plus launch. Reuse this pending version for same-day attempts; after success, record its metadata and install/launch log paths so later deployments can advance correctly.
- Before installation, verify the built host and embedded extension plists both contain the prepared `CFBundleShortVersionString` and `CFBundleVersion`; settings or an unsigned compile alone are not deployment evidence.

### Last observed configuration (verify before reuse)

- Verified on 2026-10-31: team `PD2729ZJNT` (the signing certificate subject `OU`; the `G9266R466P` in the certificate name is NOT the team ID and fails with "No Account for Team").
- App `com.phanquocviet.VocabularyWidget`, extension `com.phanquocviet.VocabularyWidget.WidgetKit`, App Group `group.com.phanquocviet.VocabularyWidget` (both entitlement files, `Shared/WidgetProgressStore.swift`, `Tests/run_progress_checks.sh`).
- Device: "PQV IPhone", iPhone 17 Pro Max, UDID `00008150-000215C11E12401C`. It may show `unavailable` until the phone is unlocked/connected; recheck `devicectl list devices`.
- Release signed build, install, and launch succeeded with these values.

## Build evidence and device-only behavior

- Keep the complete `xcodebuild` log in the build directory outside the source tree. Require both a zero exit code and `** BUILD SUCCEEDED **`; never report a failed build as successful because other checks passed.
- If a build fails, identify the first actionable diagnostic and classify it as a source, configuration/signing, or toolchain/environment failure. Keep compilation, signing, device availability, installation, and launch outcomes distinct.
- For behavior that reproduces only on a physical device—especially audio, App Intents, or background execution—capture a persistent device-side log before changing behavior. Copy the log from the device with `devicectl device copy from` and preserve it with the build evidence.
- Group device log events by `pid` and record how each process was launched (widget intent cold launch, user opening the app, or `devicectl` launch). These paths can behave differently. For widget audio checks, install the app and test by invoking the widget; do not launch the app with `devicectl process launch` first.

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

Run installation and launch as separate steps; launch only after installation succeeds. Do not uninstall the existing app or reset its App Group data. A successful app launch does not automatically add the widget to the Home Screen: open the widget gallery on the iPhone and add **Vocabulary Widget** if it is not already there.

If the device is unavailable, report the exact `devicectl` result and ask the user to unlock/trust the iPhone, enable Developer Mode if needed, or reconnect it by USB. Do not claim the app is on the phone unless installation and launch both succeed.

## 4. Finish

- Keep the successful signed build and logs available; report their exact locations.
- Report build, signing, installation, and launch as separate outcomes.
- Ask the user to check the app's topic list and the widget's word, Vietnamese meaning, part of speech, and example on the phone.
- Do not commit, push, upload, or start TestFlight/App Store distribution unless requested.
