# Local companion protocol v1

Messages are newline-delimited UTF-8 JSON over TLS 1.2 or newer. This is separate from desktop game UDP and local control. Only private IPv4 endpoints or explicit USB loopback are accepted. There is no cloud discovery, internet forwarding, or plaintext fallback.

## Pairing, remembering, and revocation

PC access is off by default and binds one selected address on TCP 44445. A locally generated OpenSSL certificate and private key identify the PC. On Unix, identity files are owner-only. On Windows, normal account-directory ACLs apply.

`abm://pair/<base64url-json>` carries `{v:1,host,port,sha256,secret}` and optionally `transport:"usb-iphone"|"usb-android"`. The SHA-256 value pins the exact DER certificate. The fresh 32-byte hex secret expires after 120 seconds. Base64 is not encryption, so keep links private. The phone checks the pin before sending `{kind:"pair",v:1,secret,device}`. The PC checks the secret and asks you to approve the self-reported name. No telemetry or game commands move before approval.

PC approval can remember the phone. It generates an independent 32-byte random token and a 32-hex device ID, saves **only the token hash** with the display name, then sends `{kind:"trusted",id,token}` over approved TLS before `ready`. ABM saves at most 16 devices in owner-only storage with atomic writes. iOS stores the endpoint, pin, and token in the WhenUnlockedThisDeviceOnly Keychain. Android stores them atomically in private app data with backup disabled. Storage failures are reported, not shown as saved approval.

Explicit Reconnect pins the same certificate, then sends `{kind:"resume",v:1,id,token}`. The PC hashes and checks it while access is enabled. Resume doesn't need the expired link or another approval. There is no automatic connection or offline queue. Stop disconnects and disables listening **without revoking saved credentials**. PC Forget devices saves the revocation and stops access. Phone Forget PC removes its local record. A stolen token plus an enabled PC endpoint gives that device access, so revoke it on the PC. Replacing the certificate requires a new pairing.

The server limits TLS handshakes to 5 seconds, unauthenticated connections to 4, input to 32 KiB, and unauthenticated idle time to 15 seconds. These aren't internet-service hardening guarantees.

## Telemetry, photos, and commands

`ready` comes before whitelisted v1 `snapshot` messages, sent every 100 ms. On a slow link, ABM skips publication instead of queuing stale frames. `catalog`, `configs`, and `configsModel` are sent when they change. Omitted keys keep their previous values. State excludes installation paths, local notes, preferences, and pairing credentials, but it does include personal gameplay, player, and server information.

Catalog and configuration `photo` and `modelPhoto` values are opaque 64-hex IDs, not file paths. An approved phone requests `{kind:"thumbnail",id}`. The PC accepts only previews referenced by its current library, decodes through its limited provider, and sends `{kind:"thumbnail",id,jpeg}` with a JPEG no larger than 320×200 and 64 KiB. It sends an empty value when unavailable. The server queue is 32. Clients pipeline at most 8 and cache at most 128 completed responses, including failures. They validate dimensions before decoding and never fetch arbitrary files or URLs. Photos come only from your running PC. Proprietary artwork isn't bundled. Model fallbacks are labeled.

`{kind:"ping",stamp}` receives `{kind:"pong",stamp}` for phone-to-PC RTT, which is separate from game ping. Approved application traffic is limited to 64 messages per second. Game commands have their own limit of 10 per second.

Each `{kind:"command",seq,action,args,target}` carries a strictly increasing connection-scoped sequence and the displayed bridge session, vehicle, generation, map, and server identity. The PC rejects stale targets. Direct action buttons don't add a second confirmation. Policy, ownership, stopped-speed, busy or preset, and bridge checks still apply. A loaded empty map can spawn without an existing vehicle. With a selected vehicle, spawn still requires it to be owned and stopped. Replace and tuning still need the current owned, stopped vehicle. Switching checks the requested owned roster entry. Receipts acknowledge backend dispatch, not verified game acceptance. Readback and game results are still the source of truth.

Fixed allowlist: catalog and configuration reads; power, RPM, clutch and reset persistence, handling, engine and gears; repair, extinguish, stability, dealer stop, full reset, and trip reset; spawn, replace, and owned switch. Some actions don't have a mobile editor. There is no arbitrary Lua, shell, file API, desktop setup, or continuous steering or throttle endpoint. More than two seconds without snapshots disables controls and clears state. Disconnect cancels queued live-power edits, not effects the game already accepted.

## USB boundary and testing limits

iPhone uses a byte-only pair of phone loopback listeners (44446 for the cable, 44447 for the TLS client), PC `iproxy` loopback 44448, and a limited PC byte bridge to MobileHost loopback 44445. Android uses an explicitly authorized, serial-scoped `adb reverse` with no-rebind and matching-rule cleanup. TLS still terminates only at MobileHost and the pinned phone client. No USB listener binds a LAN wildcard. No firewall opening, root access, or driver install happens automatically. You need foreground use, trusted USB pairing or debugging, and free fixed ports.

Synthetic TLS and game peers test pinning, approval, saved reconnect and revocation, images, library deltas, spawn, and direct commands. Loopback relays and fake helpers aren't physical-cable, real-device latency, battery, router, Windows driver, or live BeamNG/BeamMP certification. Keep pairing tokens, personal IPAs and profiles, and device logs out of source control.
