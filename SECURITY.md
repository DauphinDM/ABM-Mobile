# Security

This is an experimental local-network companion, not an Internet-facing service. Pair only on trusted private networks, keep invitations private, approve only your own request, and stop PC access when finished. Do not forward its port or expose the game receiver.

Both clients pin the invited certificate before sending credentials. The native iOS client also disconnects on backgrounding; no connection is restored automatically. Simulator fixtures contain temporary, synthetic data only; never substitute production invitations or keys in committed test resources.

See [protocol boundaries and limitations](docs/protocol.md). Report sensitive vulnerabilities privately through GitHub private vulnerability reporting if available, or contact the repository owner privately; do not publish invitations, keys, personal telemetry or an exploitable payload in a public issue. A minimal issue requesting a private contact is fine if no private channel is available.
