# ABM Mobile

Android and native iOS companions for [PC ABM](https://github.com/DauphinDM/ABM). Both connect to your PC over an encrypted link that you opt into. The Android app shares the PC app's dark Qt Quick dashboard components. The iOS app uses SwiftUI with native iOS 26 Liquid Glass navigation and controls. It is not a Qt or web wrapper.

**Early development, not a complete port.** You need PC ABM 0.13.0 or newer for Connect. The older 0.12.0 release doesn't include it. An earlier iPhone build, re-signed locally, has connected successfully over Wi-Fi. USB mode and remembered devices still need testing on real hardware. A simulator ZIP is not an installable iPhone IPA. Neither app runs BeamNG on your phone. This is not an official BeamNG or BeamMP app.

## Connect your phone

Development builds include **Connect → App updates**. This gives you opt-in release checks, verified Android downloads, and an explicit installer prompt. On iOS, ABM opens the official release instructions. You still need to sign the IPA yourself. See [update limits and publishing](docs/updates.md). CI artifacts alone do not trigger updates.

1. Put both devices on the same trusted private Wi-Fi network.
2. Open **Connect** in the updated PC app, select its LAN IPv4 address, and enable phone access. Creating the certificate the first time requires `openssl` on your PC's PATH.
3. Transfer the temporary pairing link to your phone privately. Treat it like a password. It expires after two minutes. This version has no QR scanner.
4. Paste the link into **Connect** in ABM Mobile and request approval. Approve the device on your PC only if you just started the request.
5. Leave **Remember this device** selected on the PC to save a credential you can revoke later. Next time, enable PC access and tap **Reconnect** on the phone. You won't need a new link or another approval for that saved device. Reconnecting is always explicit, never automatic.
6. **Stop access** closes the connection and listener but keeps saved devices. **Forget all remembered devices** on the PC revokes them. **Forget PC** removes the credential from your phone.

If needed, allow TCP 44445 only on the selected PC address and only on the trusted private-network firewall profile. **Never port-forward it.** Guest Wi-Fi isolation can block the connection. ABM uses no internet relay, account, UDP exposure, discovery broadcast, or automatic firewall changes.

## What the first version can do

| Screen | Available |
| --- | --- |
| Drive | Live speed, gear, RPM, fuel, temperature, and latency; local units toggle |
| Workshop / Car | Power, RPM, clutch protection, gear ratios, repair, extinguish, stabilize, and clear ABM tuning |
| Garage | PC catalog, capped live thumbnails, spawn, and replacement |
| Session | Players, copy names and addresses, owned-vehicle switching, and trip reset |
| Connect | Pinned TLS, PC approval, remembered reconnect, Wi-Fi/USB, and status |

Action buttons send directly, with no extra "Send to PC" confirmation. They still need a stopped, owned vehicle and server permission, and they pass through PC and game validation. You can spawn into a loaded empty map without an existing car. Replacing or tuning does need one. Use the keyboard **Done** action or swipe to dismiss it on iOS. Android also has a Done action while its keyboard is visible. A request receipt does not mean the game accepted the action. This app does not control steering or throttle.

Not ported yet: QR scanning, preset-file management, profile and account lookup, dimension experiments, full handling and engine editors, calculators, launcher and setup, and desktop support export. There is no offline queue and no automatic preset application.

## USB mode (experimental)

PC Connect offers **iPhone USB** and **Android USB**. Both keep TLS pinning, PC approval, remembered credentials, and game restrictions. Neither opens a LAN firewall port. ABM does not install drivers or enable debugging mode for you.

- **iPhone:** install `iproxy`/libusbmuxd on the PC, connect one unlocked iPhone, and trust the PC. Select iPhone USB on the PC and enable it, then use USB mode in the foreground iOS app and paste the generated link. The PC forwards USB port 44446 through loopback 44448. The app's loopback 44447 forwards the pinned TLS stream to PC loopback 44445. If you background the phone, the relay disconnects.
- **Android:** install `adb` on the PC, turn on USB debugging yourself, and approve that PC on one attached phone. The PC selects that device's serial and runs `adb reverse --no-rebind tcp:44445 tcp:44445`. ABM refuses existing mappings instead of replacing them. Stopping removes only ABM's matching mapping on that same device. Paste the generated loopback link on Android.

Keep the phone app open. The fixed loopback ports must be free. USB doesn't promise a specific latency. The Drive screen's **Phone ↔ PC** RTT measures this connection separately from game and server ping. Telemetry publishes at 10 Hz with TCP no-delay and library deltas. If you switch a saved Wi-Fi PC to USB, it uses the same certificate and token. If you pair over USB first, pair once over Wi-Fi to learn the PC's Wi-Fi address.

## Build and test

### Android / Qt

Desktop development needs Qt 6.8+ with Quick, Controls, Network, and Test modules, a C++17 compiler, qmake, and OpenSSL. On a machine with Qt:

```sh
./bin/build
./bin/test
./build/abm-mobile
```

Tests use a local synthetic TLS server. They check pin rejection before any secret is sent, approval, frozen command targets, stale disconnection, and all five screens at phone and tablet sizes. They don't contact a real game.

The GitHub Actions workflow also builds an **arm64 Android development APK** with Qt 6.8.3, Android API 35, NDK 26.1, and Java 17. The debug-signed APK and `SHA256SUMS` are workflow artifacts, not a Play Store release or a stable signing identity. It requires Android 9 / API 28 or newer. Extract the artifact and install the APK yourself, only on a device you choose. CI never installs anything on your phone.

Android builds run `bin/fetch-android-openssl` first, with `ANDROID_NDK_ROOT` set. The script checks the OpenSSL 3.5.9 LTS source archive checksum, builds arm64 TLS libraries, and fetches license notices. See [third-party notices](docs/THIRD-PARTY.md). Don't commit `vendor/`, build output, pairing links, private certificates, or personal telemetry.

### Native iOS

The independent `ios/` app requires **iOS 26+**, Xcode 26+ on macOS, and XcodeGen. It uses SwiftUI, Network.framework, Security, and CryptoKit instead of Qt and OpenSSL. See [iOS build and design notes](docs/ios.md). The iOS workflow builds and tests on an iPhone simulator, then archives the simulator app and XCTest results. It also provides an **unsigned arm64 device IPA** in the `ABM-Mobile-iOS-Unsigned-IPA` artifact for [signing and connectivity testing on your own iPhone](docs/ios.md#test-on-your-iphone-using-the-unsigned-ipa). Installing on a physical iPhone requires your own Apple signing setup. No Apple account, signing key, or distribution identity is included.

## Design and security

See [protocol and security notes](docs/protocol.md). The PC stays in charge. ABM exposes only fixed, validated operations. There is no remote shell, arbitrary Lua, or file API. The invitation pins the PC certificate before any secret is sent. Self-signed certificates are not trusted without that pin. Anyone with access to the PC or the link can try to pair, so approval still matters.

MIT licensed. The shared UI files come from DauphinDM/ABM at `5eda4cdd04d8f2096f5923544fcd623eead8d147`, with the new five-tab navigation and mobile layout adapted here. The game bridge, desktop file integration, and proprietary game assets are not copied into this repository.
