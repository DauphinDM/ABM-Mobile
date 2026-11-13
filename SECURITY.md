# Security

Update checks are opt-in HTTPS requests to the official GitHub repository. They never use URLs supplied by the PC or game. Android checks limited release-asset hashes before atomic acceptance and before giving the OS installer a read-only URI for a single APK. iOS only opens official release instructions. It can't silently install an IPA and never collects Apple signing credentials. There is no automatic uninstall, remote update command, or in-game interruption. Repository compromise is outside checksum protection. See [update behavior](docs/updates.md).

This is an experimental local-network companion, not an internet-facing service. Pair only on trusted private networks, keep invitations private, approve only your own request, and stop PC access when you're finished. Don't forward its port or expose the game receiver.

Both clients pin the invited certificate before sending credentials. The native iOS client also disconnects when backgrounded. No connection is restored automatically. Simulator fixtures contain only temporary, synthetic data. Never put production invitations or keys in committed test resources.

Remembered access is optional and revocable. The PC stores token hashes. iOS stores tokens in the WhenUnlockedThisDeviceOnly Keychain. Android stores them in atomic private app storage with backup disabled. Treat tokens like passwords. Stop disconnects without forgetting. Forget on the PC revokes access. Explicit reconnect still needs an enabled host and the pinned certificate. USB uses loopback-only byte relays and the same TLS, not a plaintext bypass. Optional helpers don't install drivers or enable debugging automatically. Android mappings use no-rebind and clean up only their own same-device entry.

Photos are on-demand, limited JPEGs authorized by opaque current-library IDs. They aren't arbitrary file paths or URLs. Direct Apply removes a redundant game-action confirmation, not PC approval, policy, ownership, or stopping checks, or stale-target validation. Physical USB and the new remembered-device behavior need testing. Neither client is an audited hostile-LAN service.

See [protocol boundaries and limitations](docs/protocol.md). Report sensitive vulnerabilities privately through GitHub private vulnerability reporting if it's available, or contact the repository owner privately. Don't publish invitations, keys, personal telemetry, or an exploitable payload in a public issue. A minimal issue asking for a private contact is fine if no private channel is available.
