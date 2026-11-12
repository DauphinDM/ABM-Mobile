# Native iOS companion

This is a separate SwiftUI implementation of the first mobile feature subset, using the same v1 wire protocol as Android. It does not embed Qt, a web view or Android UI. Requires **iOS 26 or newer** so native Liquid Glass is available without simulated blur/fallback controls.

## Design

- Native `TabView` and `NavigationStack` provide system Liquid Glass navigation, safe areas and accessibility.
- `.glass` and `.glassProminent` button styles are used for actions; content/telemetry cards remain opaque, readable surfaces rather than stacking glass everywhere.
- System fonts, Dynamic Type, monospaced instruments, native text editing, keyboard Done/swipe dismissal, clipboard and touch targets replace desktop widgets. Game Apply buttons send directly without an extra confirmation sheet; security approval remains on PC.
- Drive, Workshop, Garage, Session and Connect mirror the Android first-version feature subset. They do not claim complete PC parity; see the scope table in the README.

Reference: Apple's [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/) and [SwiftUI group lab](https://developer.apple.com/videos/play/wwdc2026/8120/).

## Transport and safety

`NWConnection` uses TLS 1.2 or newer and TCP no-delay. Its Security callback checks the exact leaf certificate SHA256 **before** sending pairing or resume credentials. This is a pinned identity, not a blanket certificate exception. Invitations accept only strictly parsed private IPv4/loopback. Optional remembered tokens use device-only Keychain and explicit reconnect; there is no Bonjour broadcast or cloud relay. USB uses bounded Network.framework loopback byte relays while retaining end-to-end TLS; see the README for PC helper/port setup.

Initial PC approval precedes snapshots/commands; optional saved access can later resume explicitly while the PC host is enabled. Stop retains tokens; Forget on PC revokes them. Commands carry increasing sequences and the current frozen target. Offline, stale, moving, unowned, busy or denied states disable mutations; spawning into a loaded empty map needs no existing vehicle. PC and game remain authoritative. A two-second snapshot watchdog and backgrounding disconnect. No automatic reconnect or offline queue exists.

The local-network permission text explains why access is needed. There is no global App Transport Security exception, remote scripting, filesystem API, analytics SDK or third-party networking dependency. The link field is privacy-sensitive; invitation values are never logged. Keep links out of screenshots, issue reports and source control. Local paste/copy is explicit; no QR camera permission is requested.

## Build on a Mac

```sh
brew install xcodegen
cd ios
xcodegen generate
open ABMMobile.xcodeproj
```

Choose the ABMMobile scheme and an iOS 26 iPhone simulator. To run simulator tests from the repository root:

```sh
python3 tests/ios_tls_fixture.py &
cd ios
xcodegen generate
xcodebuild test -project ABMMobile.xcodeproj -scheme ABMMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="-"
```

Stop the fixture afterward. It uses only loopback and ephemeral credentials, never a game. UI integration checks pinned TLS/approval, Garage photo delivery, exact spawn, direct power/repair, keyboard Done and stale disconnection. The fixture verifies command order, sequence and frozen target before marking success. Unit tests cover protocol/policy/empty-map gates, isolated Keychain revocation and loopback USB forwarding. Simulator builds use an ad-hoc signature and a synthetic, simulator-only Keychain identity to exercise real Keychain access without Apple credentials. That identity is SDK-scoped and never used for device IPA builds or user provisioning. CI retains `.xcresult`; simulator tests are not physical-device or live-game certification.

For a physical iPhone, select your signing team in Xcode and a unique bundle identifier if required. A real device on Wi-Fi requires the actual updated PC app, not the simulator's loopback fixture. Do not upload signing credentials or provisioning profiles to this repository. No App Store/TestFlight upload or signed IPA is currently provided.

## Test on your iPhone using the unsigned IPA

The **Native iOS** workflow builds a Release **iPhoneOS arm64** app, packaged as `ABM-Mobile-0.1.0-iOS-arm64-unsigned-build3.ipa` inside `ABM-Mobile-iOS-Unsigned-IPA`. This is a device binary, not a renamed simulator build. Verify `SHA256SUMS-ipa`. Build 3 adds photos, direct actions, keyboard dismissal, remembered access and experimental USB transport; it requires updated PC source too.

Build 2 adds the PC ABM icon as a complete iPhone/iPad asset catalog, generated icon metadata and a temporary ad-hoc signature. CI exercises `codesign` re-signing/strict verification and checks the packaged device platform, executable, icons, permissions and metadata. The ad-hoc signature is only a re-signing scaffold, **not** an Apple certificate/provisioning identity. A physical installation still requires your own valid signing configuration.

An earlier ESign no-prompt failure was traced with device logs to its manifest server returning HTTP 522 HTML instead of a plist, before IPA verification. A profile/bundle-ID mismatch in the first signed export also needed correction. The matching re-signed build 2 then installed successfully over USB and paired on Wi-Fi. This does not establish every tool/certificate's compatibility or validate new physical USB transport. Keep minimum OS 26.0 and bundle ID consistent with your own provisioning profile. Keep keys, passwords and profiles local; never submit them to this public repository.

The IPA is intentionally small: SwiftUI, Network and other Apple frameworks come from iOS. The original roughly 210 KB ZIP contained a roughly 1.07 MB executable; it did not contain Qt, game assets or a bundled game engine. Icons can be regenerated with `python3 bin/generate-ios-icons` (ImageMagick required); the committed PNGs avoid a build-time graphics-tool dependency.

The IPA is **unsigned and cannot be installed directly**. Re-sign/install it on your own iOS 26+ device using a trusted tool such as AltStore or Sideloadly, or build/sign the source with Xcode. Follow that tool's Apple-account, provisioning and Developer Mode instructions. Free provisioning can have expiry and app-count limits. Keep your Apple credentials and signing material local; do not send them to us or commit them. No signing service, TestFlight or App Store distribution is configured here.

To test connectivity:

1. Connect the iPhone and PC to the same trusted private Wi-Fi/LAN, without guest-network client isolation.
2. Open the updated **PC ABM → Connect**, select the PC's LAN address and enable phone access. Allow private-network TCP port **44445** through your firewall if needed; never forward it on your router.
3. Copy the private, short-lived pairing link to the iPhone, paste it into **ABM Mobile → Connect** and request pairing. Allow iOS Local Network access when asked.
4. Approve the phone on PC, optionally remembering it. Check telemetry first; with your own vehicle stopped and policy permitting, tap Apply directly.
5. Stop PC access when finished. Backgrounding disconnects. A remembered PC can be resumed using Reconnect while its listener is enabled; otherwise use a fresh link. Forget on PC revokes remembered access.

If Local Network access was denied, enable it in iOS Settings for ABM Mobile. A successful device build does not constitute physical-iPhone or live-game testing; the simulator's TLS integration tests use a synthetic host.
