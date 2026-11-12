import Foundation
import Combine
import Network
import Security
import UIKit
import ImageIO

@MainActor final class CompanionClient: ObservableObject {
    @Published private(set) var snapshot: JSONValue = .null
    @Published private(set) var message = "Open Connect to pair with your PC."
    @Published private(set) var connected = false
    @Published private(set) var remembered = RememberedPC.load()
    @Published private(set) var thumbnails: [String: Data] = [:]
    @Published private(set) var roundTripMS: Int?
    @Published var usbMode = false
    private let usbRelay = USBRelay()
    private var connection: NWConnection?
    private var decoder = LineDecoder()
    private var approved = false
    private var lastSnapshot: TimeInterval = 0
    private var started: TimeInterval = 0
    private var sequence = 0
    private var watchdog: Timer?
    private var endpoint: (host: String, port: UInt16, pin: String, name: String)?
    private var imageRequests = Set<String>()
    private var imageQueue: [String] = []
    private var imageFlight = Set<String>()
    private var pingAt: TimeInterval = 0
    private var storageWarning = ""

    var state: JSONValue { snapshot["state"] }
    var target: JSONValue { snapshot["target"] }
    var busy: Bool { snapshot["busy"].flag }
    var canChange: Bool { CompanionWire.mutable(state, connected: connected, busy: busy) }
    var canSpawn: Bool { CompanionWire.spawnable(state, connected: connected, busy: busy) }
    var canBrowse: Bool { connected && state["connected"].flag && state["controlsAvailable"].flag && !busy }
    var actionMessage: String { String(snapshot["actionMessage"].text.prefix(512)) }

    init() {
        usbMode = remembered?.usb ?? false
        usbRelay.failure = { [weak self] reason in self?.disconnect(reason) }
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
        usbRelay.stop()
        approved = false; connected = false; snapshot = .null
        decoder = LineDecoder(); lastSnapshot = 0; started = 0; sequence = 0
        imageRequests = []; imageQueue = []; imageFlight = []; thumbnails = [:]; roundTripMS = nil; pingAt = 0
        storageWarning = ""
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
        usbMode = invite.transport == "usb-iphone" || usbMode
        if usbMode && !usbRelay.start() { message = "Cannot start USB listeners. Close other ABM instances and retry."; return }
        endpoint = (invite.host,invite.port,invite.sha256,name)
        connect(host: invite.host, port: port, pin: invite.sha256,
                hello: .object(["kind": .string("pair"), "v": .number(1), "secret": .string(invite.secret), "device": .string(name)]))
    }
    func reconnect() {
        guard let pc = remembered, let port = NWEndpoint.Port(rawValue: pc.port) else { return }
        disconnect(); endpoint = (pc.host,pc.port,pc.pin,pc.name)
        if usbMode && !usbRelay.start() { message = "USB listeners could not start."; return }
        connect(host: pc.host, port: port, pin: pc.pin, hello: .object(["kind": .string("resume"), "v": .number(1), "id": .string(pc.id), "token": .string(pc.token)]))
    }
    func forgetPC() {
        disconnect()
        guard RememberedPC.forget() else { message = "Keychain could not remove the saved PC. Revoke this device on the PC and retry."; return }
        remembered = nil; message = "Saved PC removed from this phone. Revoke this device on the PC too if needed."
    }
    private func connect(host: String, port: NWEndpoint.Port, pin: String, hello: JSONValue) {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        // Custom trust is deliberately the exact leaf certificate from the private
        // invitation. No pairing secret is sent before Network completes this check.
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
            let reference = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let chain = SecTrustCopyCertificateChain(reference) as? [SecCertificate], let leaf = chain.first else { complete(false); return }
            complete(CompanionWire.certificateMatches(SecCertificateCopyData(leaf) as Data, pin: pin))
        }, .main)
        let tcp = NWProtocolTCP.Options(); tcp.noDelay = true
        let socket = NWConnection(host: NWEndpoint.Host(usbMode ? "127.0.0.1" : host), port: usbMode ? NWEndpoint.Port(rawValue: 44447)! : port, using: NWParameters(tls: tls, tcp: tcp))
        connection = socket; started = ProcessInfo.processInfo.systemUptime
        message = "Connecting securely to PC…"
        socket.stateUpdateHandler = { [weak self, weak socket] status in
            Task { @MainActor [weak self, weak socket] in
                guard let self, let socket, self.connection === socket else { return }
                switch status {
                case .ready:
                    self.send(hello, on: socket)
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
        case "trusted" where !approved:
            guard let endpoint, value["id"].text.count == 32, value["id"].text.allSatisfy({ $0.isHexDigit && !$0.isUppercase }), Invitation.hex(value["token"].text) else { disconnect("Invalid saved-device credential."); return }
            var pc = RememberedPC(host: endpoint.host, port: endpoint.port, pin: endpoint.pin, id: value["id"].text, token: value["token"].text, name: endpoint.name)
            pc.usb = usbMode
            if pc.save() { remembered = pc } else { storageWarning = "Connected, but Keychain could not remember this PC. Pairing will be required next time."; message = storageWarning }
        case "thumbnail" where approved:
            let id = value["id"].text
            guard imageFlight.remove(id) != nil, value["jpeg"].text.utf8.count <= 90000 else { disconnect("Invalid thumbnail response."); return }
            if thumbnails.count >= 128, let old = thumbnails.keys.first { thumbnails.removeValue(forKey: old); imageRequests.remove(old) }
            thumbnails[id] = Data() // Negative cache: unavailable previews must not loop.
            if let data = Data(base64Encoded: value["jpeg"].text), data.count <= 65536,
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
               width > 0, width <= 320, height > 0, height <= 200 {
                thumbnails[id] = data
            }
            pumpImages()
        case "pong" where approved:
            if let stamp = value["stamp"].number, stamp == pingAt { roundTripMS = Int(max(0,(ProcessInfo.processInfo.systemUptime-stamp)*1000)) }
        case "pending" where !approved: message = "Approve this iPhone in Connect on the PC."
        case "ready" where !approved:
            approved = true; lastSnapshot = ProcessInfo.processInfo.systemUptime
            message = storageWarning.isEmpty ? "PC approved. Waiting for telemetry…" : storageWarning
        case "snapshot" where approved && value["v"].number == 1:
            guard case .object = value["state"], case .object = value["target"] else { disconnect("Invalid PC snapshot."); return }
            var merged = value.object
            for key in ["catalog","configs","configsModel"] where merged[key] == nil { merged[key] = snapshot[key] }
            snapshot = .object(merged); connected = true; lastSnapshot = ProcessInfo.processInfo.systemUptime
            if message == "PC approved. Waiting for telemetry…" { message = "Connected. PC and game restrictions remain enforced." }
        case "receipt" where approved: message = String(value["message"].text.prefix(512))
        case "error": disconnect(String(value["message"].text.prefix(512)))
        default: disconnect("Unexpected PC response.")
        }
    }
    private func checkFreshness() {
        let now = ProcessInfo.processInfo.systemUptime
        if approved && now - lastSnapshot > 2 { disconnect("PC updates stopped. Controls disabled; pair again.") }
        else if !approved && started > 0 && now - started > 120 { disconnect("Pairing timed out.") }
        else if connected, let socket = connection, now-pingAt >= 2 { pingAt = now; send(.object(["kind": .string("ping"), "stamp": .number(now)]), on: socket) }
    }
    func command(_ action: String, args: [String: JSONValue] = [:], frozenTarget: JSONValue? = nil) {
        // A busy main run loop can delay the timer; never use stale telemetry
        // merely because its scheduled watchdog callback has not run yet.
        checkFreshness()
        let reads = ["catalog", "configs"]
        let changes = ["power", "rpm", "clutch", "gears", "repair", "extinguish", "stability", "fullReset", "switch", "spawn", "replace", "resetTrip"]
        guard let socket = connection, connected, canBrowse, reads.contains(action) || (changes.contains(action) && (action == "spawn" ? canSpawn : canChange)),
              frozenTarget == nil || frozenTarget == target,
              let data = try? JSONEncoder().encode(JSONValue.object(args)), data.count <= 24000, sequence < 1_000_000_000 else {
            message = "Not connected, busy, blocked or game target changed. Nothing was queued."
            return
        }
        sequence += 1
        send(.object(["kind": .string("command"), "seq": .number(Double(sequence)), "action": .string(action), "args": .object(args), "target": target]), on: socket)
    }
    func requestThumbnail(_ item: JSONValue) {
        guard connected else { return }
        for id in [item["photo"].text,item["modelPhoto"].text] where Invitation.hex(id) && !imageRequests.contains(id) && imageRequests.count < 512 {
            imageRequests.insert(id); imageQueue.append(id)
        }
        pumpImages()
    }
    private func pumpImages() {
        guard connected, let socket = connection else { return }
        while imageFlight.count < 8 && !imageQueue.isEmpty {
            let id = imageQueue.removeFirst(); imageFlight.insert(id)
            send(.object(["kind": .string("thumbnail"), "id": .string(id)]), on: socket)
        }
    }
}
