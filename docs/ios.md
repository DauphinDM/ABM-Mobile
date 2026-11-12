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
