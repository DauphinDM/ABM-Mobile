# Local companion protocol v1

Transport is newline-delimited UTF-8 JSON over TLS 1.2 or later. It is deliberately not the desktop receiver's UDP or local-socket protocol. Only private IPv4 endpoints are accepted; loopback exists for isolated development tests. This is a network boundary, not a guarantee that every private-address peer is trustworthy. No cloud discovery or forwarding is implemented.

## Pairing and lifetime

PC access is off by default and binds one explicitly selected address (default TCP 44445). The PC creates a local RSA certificate/private key using OpenSSL. On Unix the identity directory/key are owner-only; Windows users should keep the application configuration directory protected by their normal account ACLs. Private-key backup and ACL hardening are not automated on Windows.

`abm://pair/<base64url-json>` contains `{v:1,host,port,sha256,secret}`. `sha256` pins the DER certificate; `secret` is a fresh 32-byte random capability encoded as 64 hex characters. Base64 is not encryption. The copied invitation must be transferred privately. It is neither saved by the app nor placed in logs intentionally; your clipboard/transfer application can retain it.

After TLS encryption the phone compares the certificate fingerprint **before** transmitting `{kind:"pair",v:1,secret,device}`. The PC validates the secret and asks its user to approve the self-reported device name. No telemetry or commands are granted before approval. The invitation expires after 120 seconds and is consumed on approval. One approved connection is supported, with no persisted authentication or automatic reconnect. Stop revokes approvals and sockets immediately. Re-pairing requires stop/enable and a new link.

The PC bounds TLS handshake time (5 seconds), unauthenticated application connections (4), pairing input (32 KiB) and unauthenticated idle time (15 seconds). These limits do not make the service suitable for the public Internet or eliminate denial-of-service risks on a hostile LAN.

## Snapshots and commands

The PC sends `ready`, then protocol-v1 `snapshot` messages every 250 ms. State is an explicit whitelist, excluding desktop paths, local notes, preferences and profile credentials. Catalog/configuration image paths and image-provider URLs are removed. State contains gameplay identity/telemetry/players/server address and can still be personal; only pair a phone you trust.

Each command includes a strictly increasing integer `seq`, `action`, `args` and the last displayed target tuple: bridge session, game vehicle ID, workshop generation, map, server IP and port. The PC rejects stale targets rather than silently applying to a different car or server. Sequences are connection-scoped and commands are limited to 10 per second. Payloads and pending output are bounded. The phone disables controls and clears state if snapshots stop for more than two seconds; it does not queue commands offline.

Only a fixed allowlist is routed through existing Backend methods. Mutations additionally require connected bridge/control support, no busy/preset operation, known stopped speed, owned current vehicle, no join/cleanup, and sandbox permission. Switching checks the requested ID against the owned roster. The receiver/game retain their own validation. Mobile UI confirmations are dismissed on target changes; the host checks the tuple independently. A receipt means dispatch was attempted, not that the game accepted or verified it. Subsequent readback/action messages remain authoritative.

Current allowlist: catalog/configuration reads; power, RPM, clutch/reset persistence, handling, engine and gear settings; repair, extinguish, stability, stop dealer effect, full tuning reset, trip reset; spawn/replace and owned-vehicle switching. Some host operations intentionally have no mobile editor yet. There is no shell, arbitrary Lua, file read/write, desktop setup, profile lookup or continuous input endpoint.

## Testing limits

Automated tests use synthetic local TLS peers and fake game UDP endpoints. They cover approval/pinning/staleness and host command fences; they do not establish real Android TLS, touch/keyboard/insets, suspend/resume, battery behavior, Windows firewall behavior, router reachability or live BeamNG/BeamMP correctness. Test on a physical device before treating the app as reliable.
