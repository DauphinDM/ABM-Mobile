# Security

This is an experimental local-network companion, not an Internet-facing service. Pair only on trusted private networks, keep invitations private, approve only your own request, and stop PC access when finished. Do not forward its port or expose the game receiver.

Both clients pin the invited certificate before sending credentials. The native iOS client also disconnects on backgrounding; no connection is restored automatically. Simulator fixtures contain temporary, synthetic data only; never substitute production invitations or keys in committed test resources.

Remembered access is optional and revocable. PC stores token hashes; iOS stores tokens in WhenUnlockedThisDeviceOnly Keychain and Android in atomic private app storage with backup disabled. Treat tokens as passwords. Stop disconnects without forgetting; Forget on PC revokes access. Explicit reconnect still needs an enabled host and the pinned certificate. USB uses loopback-only byte relays and the same TLS, not a plaintext bypass. Optional helpers do not install drivers or automatically enable debugging. Android mappings use no-rebind and matching same-device cleanup.

Photos are on-demand, bounded JPEGs authorized by opaque current-library IDs, not arbitrary file paths or URLs. Direct Apply removes a redundant game-action confirmation, not PC approval, policy/ownership/stopping checks or stale-target validation. Physical USB and new remembered-device behavior require testing; neither client is an audited hostile-LAN service.

See [protocol boundaries and limitations](docs/protocol.md). Report sensitive vulnerabilities privately through GitHub private vulnerability reporting if available, or contact the repository owner privately; do not publish invitations, keys, personal telemetry or an exploitable payload in a public issue. A minimal issue requesting a private contact is fine if no private channel is available.
