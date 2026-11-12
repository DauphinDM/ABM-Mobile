# ABM Mobile

Android and native iOS companions for [PC ABM](https://github.com/DauphinDM/ABM), with an opt-in, encrypted connection to your PC. Android shares the PC's dark Qt Quick dashboard components. iOS uses SwiftUI with native iOS 26 Liquid Glass navigation and controls, not a Qt or web wrapper.

**Early development, not a complete port.** Requires the current PC Connect implementation; released PC ABM 0.12.0 does not include it. An earlier locally re-signed iPhone build has connected successfully over Wi-Fi. New USB and remembered-device functionality still needs physical-device verification. A simulator ZIP is not an installable iPhone IPA. Neither app runs BeamNG on the phone. This is not an official BeamNG or BeamMP app.

## Connect your phone

1. Put both devices on the same trusted private Wi-Fi network.
2. Open **Connect** in the updated PC app, select its LAN IPv4 address and enable phone access. First-time certificate generation requires `openssl` on the PC's PATH.
3. Privately transfer the temporary pairing link to your phone. Treat it as a password; it expires after two minutes. There is no QR scanner in this version.
4. Paste it into **Connect** in ABM Mobile and request approval. Approve your device on the PC only if you just initiated the request.
5. Leave **Remember this device** selected on PC to save a revocable credential. Next time enable PC access and tap **Reconnect** on the phone; no new link/approval is needed for that saved device. Reconnection is explicit, not automatic.
6. **Stop access** closes the connection/listener but keeps saved devices. **Forget all remembered devices** on PC revokes them; **Forget PC** removes the phone's local credential.

Allow TCP 44445 only on the selected PC address and trusted private-network firewall profile if necessary. **Never port-forward it.** Guest Wi-Fi isolation may prevent connections. No Internet relay, account, UDP exposure, discovery broadcast or automatic firewall changes are used.

## First-version scope

| Screen | Available |
| --- | --- |
| Drive | Live speed, gear, RPM, fuel, temperature and latency; local units toggle |
| Workshop / Car | Power, RPM, clutch protection, gear ratios, repair, extinguish, stabilize and clear ABM tuning |
| Garage | PC catalog, bounded live thumbnails, spawn and replacement |
| Session | Players, copy names/address, owned-vehicle switching and trip reset |
| Connect | Pinned TLS, PC approval, remembered reconnect, Wi-Fi/USB and status |

Action buttons send directly, without an extra “Send to PC” confirmation. They still require a stopped, owned vehicle and server permission, and pass through PC/game validation. Spawning into a loaded empty map does not require an existing car; replacing or tuning does. Use the keyboard **Done** action or drag to dismiss it on iOS; Android also has a Done action while its keyboard is visible. A request receipt is not verified game acceptance. This is not steering/throttle control.

Not yet ported: QR scanning, preset-file management, profile/account lookup, dimension experiments, full handling/engine editors, calculators, launcher/setup and desktop support export. No offline queue or automatic preset application.

## USB mode (experimental)

PC Connect offers **iPhone USB** and **Android USB**. Both keep TLS pinning, PC approval/remembered credentials, and game restrictions; neither opens a LAN firewall port. No driver or debugging mode is installed/enabled automatically.

- **iPhone:** install `iproxy`/libusbmuxd on PC, connect one unlocked iPhone and trust the PC. Select iPhone USB on PC, enable it, then use USB mode in the foreground iOS app and paste the generated link. PC forwards USB port 44446 through loopback 44448; the app's loopback 44447 forwards the pinned TLS stream to PC loopback 44445. Phone backgrounding disconnects the relay.
- **Android:** install `adb` on PC, explicitly enable USB debugging and approve that PC on one attached phone. PC selects that device's serial and creates `adb reverse --no-rebind tcp:44445 tcp:44445`. Existing mappings are refused, not replaced; stopping removes only ABM's matching mapping on that same device. Paste the generated loopback link on Android.

Keep the phone app open. Fixed loopback ports must be free. USB does not promise a particular latency: the Drive screen's **Phone ↔ PC** RTT measures this connection separately from game/server ping. Telemetry now publishes at 10 Hz with TCP no-delay and library deltas. Switching a saved Wi-Fi PC to USB uses its same certificate/token; after pairing USB-first, pair with a LAN link to learn the PC's Wi-Fi address.

## Build and test

### Android / Qt

Desktop development needs Qt 6.8+ with Quick/Controls/Network/Test, a C++17 compiler, qmake and OpenSSL. On a machine with Qt:

```sh
./bin/build
./bin/test
./build/abm-mobile
```

Tests use a local synthetic TLS server, check pin rejection before secret transmission, approval, frozen command targets, stale disconnection and all five screens at phone/tablet sizes. They do not contact a real game.

The GitHub Actions workflow also builds an **arm64 Android development APK** using Qt 6.8.3, Android API 35, NDK 26.1 and Java 17. The debug-signed APK and `SHA256SUMS` are workflow artifacts, not a Play Store release or a stable signing identity. Requires Android 9/API 28 or newer. Extract the artifact and install the APK manually only on a device you choose; CI does not install anything on your phone.

Android builds first run `bin/fetch-android-openssl` with `ANDROID_NDK_ROOT` set. It verifies the OpenSSL 3.5.9 LTS source archive checksum, builds arm64 TLS libraries and fetches license notices; see [third-party notices](docs/THIRD-PARTY.md). Do not commit `vendor/`, build output, pairing links, private certificates or personal telemetry.

### Native iOS

The independent `ios/` app requires **iOS 26+**, Xcode 26+ on macOS and XcodeGen. It uses SwiftUI, Network.framework, Security and CryptoKit, not Qt/OpenSSL. See [iOS build and design notes](docs/ios.md). The iOS workflow builds/tests on an iPhone simulator and archives the simulator app plus XCTest results. It also provides an **unsigned arm64 device IPA** in the `ABM-Mobile-iOS-Unsigned-IPA` artifact for [user-side signing and connectivity testing](docs/ios.md#test-on-your-iphone-using-the-unsigned-ipa). Installing on a physical iPhone requires your own Apple signing configuration; no Apple account, signing key or distribution identity is included.

## Design and security

See [protocol/security notes](docs/protocol.md). The PC remains the authority and only fixed, validated operations are exposed—no remote shell, arbitrary Lua or file API. The invitation pins the PC certificate before any secret is sent; self-signed certificates are not trusted without that pin. Anyone with PC access or the link may attempt pairing, so approval still matters.

MIT licensed. Shared UI files originate from DauphinDM/ABM at `5eda4cdd04d8f2096f5923544fcd623eead8d147`, with the new five-tab navigation and mobile layout adapted here. The game bridge, desktop file integration and proprietary game assets are not copied into this repository.
