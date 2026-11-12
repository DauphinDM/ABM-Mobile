# Native iOS companion

This is a separate SwiftUI implementation of the first mobile feature subset, using the same v1 wire protocol as Android. It does not embed Qt, a web view or Android UI. Requires **iOS 26 or newer** so native Liquid Glass is available without simulated blur/fallback controls.

## Design

- Native `TabView` and `NavigationStack` provide system Liquid Glass navigation, safe areas and accessibility.
- `.glass` and `.glassProminent` button styles are used for actions; content/telemetry cards remain opaque, readable surfaces rather than stacking glass everywhere.
- System fonts, Dynamic Type, monospaced instruments, native confirmation sheets, text editing, clipboard and touch targets replace desktop-specific widgets.
- Drive, Workshop, Garage, Session and Connect mirror the Android first-version feature subset. They do not claim complete PC parity; see the scope table in the README.

Reference: Apple's [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/) and [SwiftUI group lab](https://developer.apple.com/videos/play/wwdc2026/8120/).

## Transport and safety

`NWConnection` uses TLS 1.2 or newer. Its Security verify callback compares the exact leaf certificate's SHA256 against the private invitation **before** sending the pairing secret. This is an explicit pinned identity, not a blanket self-signed-certificate exception. Direct connections accept only strictly parsed private IPv4/loopback invitations; the app has no Bonjour broadcast, cloud relay or saved credentials.

PC approval precedes snapshots/commands. Commands carry increasing sequences and the frozen session/vehicle/map/generation/server target. Confirmation closes on a target change or disconnect; offline, stale, moving, unowned, busy or denied states disable mutations. The PC and game still perform authoritative validation. A two-second snapshot watchdog disconnects; entering the background also disconnects. No automatic reconnect or offline command queue exists.

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
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

Stop the fixture process afterward. It binds only loopback, creates an ephemeral certificate/secret and writes an ignored test resource. It never talks to a game. The native UI integration test exercises pinned TLS, approval, confirmed repair and stale disconnection against this synthetic host. Unit tests cover invitation/address limits, pin mismatch, framing, policy gates and no offline queue. UI tests also check all five native tabs/offline safety. CI retains `.xcresult` evidence; simulator tests are not physical-device or live-game certification.

For a physical iPhone, select your signing team in Xcode and a unique bundle identifier if required. A real device on Wi-Fi requires the actual updated PC app, not the simulator's loopback fixture. Do not upload signing credentials or provisioning profiles to this repository. No App Store/TestFlight upload or signed IPA is currently provided.

## Test on your iPhone using the unsigned IPA

The **Native iOS** workflow also builds a Release **iPhoneOS arm64** app, packaged as `ABM-Mobile-0.1.0-iOS-arm64-unsigned.ipa` inside the `ABM-Mobile-iOS-Unsigned-IPA` artifact. This is a device binary, not a renamed simulator build. Verify it using the accompanying `SHA256SUMS-ipa`.

The IPA is **unsigned and cannot be installed directly**. Re-sign/install it on your own iOS 26+ device using a trusted tool such as AltStore or Sideloadly, or build/sign the source with Xcode. Follow that tool's Apple-account, provisioning and Developer Mode instructions. Free provisioning can have expiry and app-count limits. Keep your Apple credentials and signing material local; do not send them to us or commit them. No signing service, TestFlight or App Store distribution is configured here.

To test connectivity:

1. Connect the iPhone and PC to the same trusted private Wi-Fi/LAN, without guest-network client isolation.
2. Open the updated **PC ABM → Connect**, select the PC's LAN address and enable phone access. Allow private-network TCP port **44445** through your firewall if needed; never forward it on your router.
3. Copy the private, short-lived pairing link to the iPhone, paste it into **ABM Mobile → Connect** and request pairing. Allow iOS Local Network access when asked.
4. Approve the named phone on the PC. First check live telemetry; then, with your own vehicle stopped and game policy permitting, confirm an action on the phone.
5. Stop phone access on the PC when finished. Backgrounding the iPhone app disconnects; reconnecting requires a new invitation and approval.

If Local Network access was denied, enable it in iOS Settings for ABM Mobile. A successful device build does not constitute physical-iPhone or live-game testing; the simulator's TLS integration tests use a synthetic host.
