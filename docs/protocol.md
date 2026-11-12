# Local companion protocol v1

Newline-delimited UTF-8 JSON over TLS 1.2+, separate from desktop game UDP/local control. Only private IPv4 endpoints or explicit USB loopback are accepted. No cloud discovery, Internet forwarding or plaintext fallback.

## Pairing, remembering and revocation

PC access is off by default and binds one selected address (TCP 44445). A local OpenSSL-generated certificate/private key identifies the PC. Unix identity files are owner-only; Windows relies on normal account-directory ACLs.

`abm://pair/<base64url-json>` carries `{v:1,host,port,sha256,secret}` and optionally `transport:"usb-iphone"|"usb-android"`. SHA-256 pins the exact DER certificate; the fresh 32-byte hex secret expires after 120 seconds. Base64 is not encryption: keep links private. The phone verifies the pin before sending `{kind:"pair",v:1,secret,device}`. The PC checks the secret and requests explicit approval of the self-reported name. No telemetry or game commands before approval.

PC approval may remember the phone. It generates an independent 32-byte random token and 32-hex device ID, saves **only the token hash** with the display name, then sends `{kind:"trusted",id,token}` over approved TLS before `ready`. Maximum 16 saved devices, bounded atomic owner-only storage. iOS stores the endpoint/pin/token in WhenUnlockedThisDeviceOnly Keychain; Android stores it atomically in private app data with backup disabled. Storage failures are reported, not represented as saved approval.

Explicit Reconnect pins the same certificate, then sends `{kind:"resume",v:1,id,token}`; the PC hashes/checks it while access is enabled. Resume needs neither the expired link nor another approval. No automatic connection or offline queue. Stop disconnects and disables listening **without revoking saved credentials**. PC Forget devices saves revocation and stops access; phone Forget PC removes its local record. A stolen token plus the enabled PC endpoint permits that device's access: revoke it on PC. Certificate replacement requires a new pairing.

The server bounds TLS handshake (5 seconds), unauthenticated connections (4), input (32 KiB) and unauthenticated idle time (15 seconds). These are not Internet-service hardening guarantees.

## Telemetry, photos and commands

`ready` precedes whitelisted v1 `snapshot` messages every 100 ms. Slow-link backpressure skips publication rather than queueing stale frames. `catalog`, `configs`, `configsModel` are sent on change; omitted keys retain their previous values. State excludes installation paths, local notes/preferences and pairing credentials, but includes personal gameplay/player/server information.

Catalog/configuration `photo` and `modelPhoto` are opaque 64-hex IDs, not file paths. An approved phone requests `{kind:"thumbnail",id}`. PC accepts only previews referenced by its current library, decodes through its bounded provider, and sends `{kind:"thumbnail",id,jpeg}` with JPEG at most 320×200 and 64 KiB (empty on unavailable). Server queue 32; clients pipeline at most 8, cache at most 128 completed responses including failures, validate dimensions before decoding, and never fetch arbitrary files/URLs. Photos are requested only from the user's running PC; proprietary artwork is not bundled. Model fallbacks are labeled.

`{kind:"ping",stamp}` receives `{kind:"pong",stamp}` for phone↔PC RTT, distinct from game ping. Approved application traffic is bounded to 64 messages/second; game commands retain their separate 10/second limit.

Each `{kind:"command",seq,action,args,target}` carries a strictly increasing connection-scoped sequence and the displayed bridge session/vehicle/generation/map/server identity. The PC rejects stale targets. Direct action buttons intentionally do not add a second confirmation; authoritative policy, ownership, stopped-speed, busy/preset and bridge fences remain. A loaded empty map may spawn without an existing vehicle; with a selected vehicle, spawn still requires it to be owned and stopped. Replacing/tuning still require the current owned stopped vehicle. Switching checks the requested owned roster entry. Receipts acknowledge backend dispatch, not verified game acceptance; readback/results remain authoritative.

Fixed allowlist: catalog/config reads; power, RPM, clutch/reset persistence, handling, engine/gears; repair/extinguish/stability/dealer stop/full reset/trip reset; spawn/replace/owned switch. Some lack a mobile editor. No arbitrary Lua, shell, file API, desktop setup or continuous steering/throttle endpoint. More than two seconds without snapshots disables controls and clears state; disconnect cancels queued live-power edits, not already accepted effects.

## USB boundary and testing limits

iPhone uses a byte-only pair of phone loopback listeners (44446 cable, 44447 TLS client), PC `iproxy` loopback 44448 and a bounded PC byte bridge to MobileHost loopback 44445. Android uses an explicitly authorized, serial-scoped `adb reverse` with no-rebind and matching-rule cleanup. TLS still terminates only at MobileHost and the pinned phone client. No USB listener binds a LAN wildcard; no firewall opening/root/driver install happens automatically. Foreground use, trusted USB pairing/debugging and free fixed ports are required.

Synthetic TLS/game peers test pinning, approval, saved reconnect/revocation, images, library deltas, spawn and direct commands. Loopback relays/fake helpers are not physical-cable, real-device latency, battery, router, Windows driver or live BeamNG/BeamMP certification. Keep all pairing tokens, personal IPAs/profiles and device logs out of source control.
