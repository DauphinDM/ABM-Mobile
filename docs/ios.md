# Native iOS companion

This is a separate SwiftUI implementation of the first mobile feature subset. It uses the same v1 wire protocol as Android. It doesn't embed Qt, a web view, or Android UI. It requires **iOS 26 or newer** so native Liquid Glass is available without simulated blur or fallback controls.

## Design

- Native `TabView` and `NavigationStack` provide system Liquid Glass navigation, safe areas, and accessibility.
- `.glass` and `.glassProminent` button styles are used for actions. Content and telemetry cards stay opaque and readable instead of stacking glass everywhere.
- System fonts, Dynamic Type, monospaced instruments, native text editing, keyboard Done and swipe dismissal, clipboard, and touch targets replace desktop widgets. Game Apply buttons send directly without an extra confirmation sheet. Security approval stays on the PC.
- Drive, Workshop, Garage, Session, and Connect match the Android first-version feature subset. They don't claim full PC parity. See the scope table in the README.

Reference: Apple's [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/) and [SwiftUI group lab](https://developer.apple.com/videos/play/wwdc2026/8120/).

## Transport and safety

`NWConnection` uses TLS 1.2 or newer and TCP no-delay. Its Security callback checks the exact leaf certificate SHA-256 **before** sending pairing or resume credentials. This is a pinned identity, not a blanket certificate exception. Invitations accept only strictly parsed private IPv4 or loopback. Optional remembered tokens use the device-only Keychain and explicit reconnect. There's no Bonjour broadcast or cloud relay. USB uses limited Network.framework loopback byte relays while keeping end-to-end TLS. See the README for PC helper and port setup.

Initial PC approval comes before snapshots and commands. Optional saved access can resume later while the PC host is enabled. Stop keeps tokens. Forget on the PC revokes them. Commands carry increasing sequences and the current frozen target. Offline, stale, moving, unowned, busy, or denied states disable mutations. Spawning into a loaded empty map doesn't need an existing vehicle. The PC and game remain in charge. A two-second snapshot watchdog with a short confirmation before disconnecting, plus backgrounding, disables control. There is no automatic reconnect or offline queue.

The local-network permission text explains why access is needed. There is no global App Transport Security exception, remote scripting, filesystem API, analytics SDK, or third-party networking dependency. The link field is privacy-sensitive, and invitation values are never logged. Keep links out of screenshots, issue reports, and source control. Local paste and copy are explicit. ABM doesn't request camera permission for QR scanning.

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

Stop the fixture afterward. It uses only loopback and ephemeral credentials, never a game. UI integration checks pinned TLS and approval, Garage photo delivery, exact spawn, direct power and repair, keyboard Done, and stale disconnection. The fixture verifies command order, sequence, and frozen target before marking success. Unit tests cover protocol and policy gates, empty-map gating, isolated Keychain revocation, and loopback USB forwarding. Simulator builds use an ad-hoc signature and a synthetic, simulator-only Keychain identity so they can exercise real Keychain access without Apple credentials. That identity is SDK-scoped and never used for device IPA builds or user provisioning. CI keeps `.xcresult`. Simulator tests aren't physical-device or live-game certification.

For a physical iPhone, select your signing team in Xcode and a unique bundle identifier if needed. A real device on Wi-Fi needs the actual updated PC app, not the simulator's loopback fixture. Don't upload signing credentials or provisioning profiles to this repository. No App Store or TestFlight upload and no signed IPA are provided right now.

## Test on your iPhone using the unsigned IPA

The **Native iOS** workflow builds a Release **iPhoneOS arm64** app and packages it as `ABM-Mobile-0.2.0-iOS-arm64-unsigned-build5.ipa` inside `ABM-Mobile-iOS-Unsigned-IPA`. This is a device binary, not a renamed simulator build. Verify `SHA256SUMS-ipa`. Build 5 adds opt-in release checks, limited Garage photos, direct actions, keyboard dismissal, remembered access, and experimental USB transport. It needs PC ABM 0.13.0 or newer.

Build 2 added the PC ABM icon as a complete iPhone and iPad asset catalog, generated icon metadata, and a temporary ad-hoc signature. CI exercises `codesign` re-signing and strict verification, then checks the packaged device platform, executable, icons, permissions, and metadata. The ad-hoc signature is only a re-signing scaffold, **not an Apple certificate or provisioning identity**. A physical installation still needs your own valid signing setup.

An earlier ESign no-prompt failure was traced with device logs to its manifest server returning HTTP 522 HTML instead of a plist, before IPA verification. A profile and bundle-ID mismatch in the first signed export also needed correction. The matching re-signed build 2 then installed successfully over USB and paired on Wi-Fi. That doesn't establish compatibility with every tool or certificate, and it doesn't validate the new physical USB transport. Keep minimum OS 26.0 and the bundle ID consistent with your own provisioning profile. Keep keys, passwords, and profiles local. Never submit them to this public repository.

The IPA stays small. SwiftUI, Network, and other Apple frameworks come from iOS. The original roughly 210 KB ZIP contained a roughly 1.07 MB executable. It didn't contain Qt, game assets, or a bundled game engine. You can regenerate icons with `python3 bin/generate-ios-icons` (ImageMagick required). The committed PNGs avoid a build-time graphics-tool dependency.

The IPA is **unsigned and can't be installed directly**. Re-sign and install it on your own iOS 26+ device with a trusted tool such as AltStore or Sideloadly, or build and sign the source with Xcode. Follow that tool's Apple account, provisioning, and Developer Mode instructions. Free provisioning can have expiry and app-count limits. Keep your Apple credentials and signing material local. Don't send them to us or commit them. No signing service, TestFlight, or App Store distribution is configured here.

To test connectivity:

1. Connect the iPhone and PC to the same trusted private Wi-Fi or LAN, without guest-network client isolation.
2. Open the updated **PC ABM → Connect**, select the PC's LAN address, and enable phone access. Allow private-network TCP port **44445** through your firewall if needed. Never forward it on your router.
3. Copy the private, short-lived pairing link to the iPhone, paste it into **ABM Mobile → Connect**, and request pairing. Allow iOS Local Network access when asked.
4. Approve the phone on the PC, optionally remembering it. Check telemetry first. With your own vehicle stopped and policy permitting, tap Apply directly.
5. Stop PC access when you're finished. Backgrounding disconnects. A remembered PC can be resumed with Reconnect while its listener is enabled. Otherwise use a fresh link. Forget on the PC revokes remembered access.

If Local Network access was denied, enable it in iOS Settings for ABM Mobile. A successful device build doesn't constitute physical-iPhone or live-game testing. The simulator's TLS integration tests use a synthetic host.
