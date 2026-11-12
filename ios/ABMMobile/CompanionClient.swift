import Foundation
import Combine
import Network
import Security

struct GameRequest: Identifiable {
    let id = UUID()
    let title: String
    let action: String
    let args: [String: JSONValue]
    let target: JSONValue
}

@MainActor final class CompanionClient: ObservableObject {
    @Published private(set) var snapshot: JSONValue = .null
    @Published private(set) var message = "Open Connect to pair with your PC."
    @Published private(set) var connected = false
    private var connection: NWConnection?
    private var decoder = LineDecoder()
    private var approved = false
    private var lastSnapshot: TimeInterval = 0
    private var started: TimeInterval = 0
    private var sequence = 0
    private var watchdog: Timer?

    var state: JSONValue { snapshot["state"] }
    var target: JSONValue { snapshot["target"] }
    var busy: Bool { snapshot["busy"].flag }
    var canChange: Bool { CompanionWire.mutable(state, connected: connected, busy: busy) }
    var canBrowse: Bool { connected && state["connected"].flag && state["controlsAvailable"].flag && !busy }
    var actionMessage: String { String(snapshot["actionMessage"].text.prefix(512)) }

    init() {
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            // Main run-loop timer; all connection state is confined to this actor.
            Task { @MainActor [weak self] in self?.checkFreshness() }
        }
    }
    deinit { watchdog?.invalidate(); connection?.cancel() }

    func disconnect(_ reason: String = "Disconnected. Pair again on the PC to reconnect.") {
        let old = connection
        connection = nil
        old?.cancel()
        approved = false; connected = false; snapshot = .null
        decoder = LineDecoder(); lastSnapshot = 0; started = 0; sequence = 0
        message = reason
    }

    func pair(link: String, device: String) {
        disconnect()
        let name = device.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf16.count <= 64, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let invite = try? Invitation.parse(link.trimmingCharacters(in: .whitespacesAndNewlines)),
              let port = NWEndpoint.Port(rawValue: invite.port) else {
            message = "Paste a valid private-Wi-Fi invitation and a device name (1–64 characters)."
            return
        }
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        // Custom trust is deliberately the exact leaf certificate from the private
        // invitation. No pairing secret is sent before Network completes this check.
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
            let reference = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let chain = SecTrustCopyCertificateChain(reference) as? [SecCertificate], let leaf = chain.first else { complete(false); return }
            complete(CompanionWire.certificateMatches(SecCertificateCopyData(leaf) as Data, pin: invite.sha256))
        }, .main)
        let socket = NWConnection(host: NWEndpoint.Host(invite.host), port: port, using: NWParameters(tls: tls, tcp: NWProtocolTCP.Options()))
        connection = socket; started = ProcessInfo.processInfo.systemUptime
        message = "Connecting securely to PC…"
        socket.stateUpdateHandler = { [weak self, weak socket] status in
            Task { @MainActor [weak self, weak socket] in
                guard let self, let socket, self.connection === socket else { return }
                switch status {
                case .ready:
                    self.send(.object(["kind": .string("pair"), "v": .number(1), "secret": .string(invite.secret), "device": .string(name)]), on: socket)
                    // Drop the credential-bearing handler after the handshake.
                    socket.stateUpdateHandler = { [weak self, weak socket] status in
                        Task { @MainActor [weak self, weak socket] in
                            guard let self, let socket, self.connection === socket else { return }
                            if case .failed = status { self.disconnect("Connection failed. Check Wi-Fi, the invitation and PC approval.") }
                            if case .cancelled = status { self.disconnect() }
                        }
                    }
                    self.receive(on: socket)
                case .failed: self.disconnect("TLS connection failed. Check Wi-Fi and the PC certificate invitation.")
                case .cancelled: self.disconnect()
                default: break
                }
            }
        }
        socket.start(queue: .main)
    }

    private func send(_ value: JSONValue, on socket: NWConnection) {
        guard let encoded = try? JSONEncoder().encode(value), encoded.count <= 32768 else { disconnect("Command exceeded the size limit."); return }
        socket.send(content: encoded + Data([10]), completion: .contentProcessed { [weak self, weak socket] error in
            Task { @MainActor [weak self, weak socket] in
                guard let self, let socket, self.connection === socket else { return }
                if error != nil { self.disconnect("Connection lost. Nothing is queued for reconnect.") }
            }
        })
    }
    private func receive(on socket: NWConnection) {
        socket.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak socket] data, _, complete, error in
            Task { @MainActor [weak self, weak socket] in
                guard let self, let socket, self.connection === socket else { return }
                do {
                    if let data { for value in try self.decoder.append(data) {
                        self.accept(value)
                        guard self.connection === socket else { return }
                    } }
                } catch { self.disconnect("Invalid or oversized PC response."); return }
                if complete || error != nil { self.disconnect("PC disconnected. All controls disabled."); return }
                self.receive(on: socket)
            }
        }
    }
    private func accept(_ value: JSONValue) {
        switch value["kind"].text {
        case "pending" where !approved: message = "Approve this iPhone in Connect on the PC."
        case "ready" where !approved:
            approved = true; lastSnapshot = ProcessInfo.processInfo.systemUptime
            message = "PC approved. Waiting for telemetry…"
        case "snapshot" where approved && value["v"].number == 1:
            guard case .object = value["state"], case .object = value["target"] else { disconnect("Invalid PC snapshot."); return }
            snapshot = value; connected = true; lastSnapshot = ProcessInfo.processInfo.systemUptime
            message = "Connected. PC and game restrictions remain enforced."
        case "receipt" where approved: message = String(value["message"].text.prefix(512))
        case "error": disconnect(String(value["message"].text.prefix(512)))
        default: disconnect("Unexpected PC response.")
        }
    }
    private func checkFreshness() {
        let now = ProcessInfo.processInfo.systemUptime
        if approved && now - lastSnapshot > 2 { disconnect("PC updates stopped. Controls disabled; pair again.") }
        else if !approved && started > 0 && now - started > 120 { disconnect("Pairing timed out.") }
    }
    func command(_ action: String, args: [String: JSONValue] = [:], frozenTarget: JSONValue? = nil) {
        // A busy main run loop can delay the timer; never use stale telemetry
        // merely because its scheduled watchdog callback has not run yet.
        checkFreshness()
        let reads = ["catalog", "configs"]
        let changes = ["power", "rpm", "clutch", "gears", "repair", "extinguish", "stability", "fullReset", "switch", "spawn", "replace", "resetTrip"]
        guard let socket = connection, connected, canBrowse, reads.contains(action) || (changes.contains(action) && canChange),
              frozenTarget == nil || frozenTarget == target,
              let data = try? JSONEncoder().encode(JSONValue.object(args)), data.count <= 24000, sequence < 1_000_000_000 else {
            message = "Not connected, busy, blocked or game target changed. Nothing was queued."
            return
        }
        sequence += 1
        send(.object(["kind": .string("command"), "seq": .number(Double(sequence)), "action": .string(action), "args": .object(args), "target": target]), on: socket)
    }
}
