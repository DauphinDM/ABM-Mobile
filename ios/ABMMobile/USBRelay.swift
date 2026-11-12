import Foundation
import Network

// A byte-only loopback bridge. iproxy reaches port 44446 over the trusted USB
// pairing; the normal pinned TLS client uses 44447. This never terminates TLS.
@MainActor final class USBRelay {
    private var listeners: [NWListener] = []
    private var cable: NWConnection?
    private var local: NWConnection?
    private var cableReady = false
    private var localReady = false
    private var pumping = false
    var failure: ((String) -> Void)?

    func start() -> Bool {
        stop()
        do {
            for port in [UInt16(44446), UInt16(44447)] {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
                let listener = try NWListener(using: parameters)
                listener.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor [weak self] in self?.accept(connection, cable: port == 44446) }
                }
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    Task { @MainActor [weak self, weak listener] in
                        guard let self, let listener, self.listeners.contains(where: { $0 === listener }) else { return }
                        if case .failed = state { self.stop(); self.failure?("USB loopback listener failed. Disconnect and retry USB mode.") }
                    }
                }
                listeners.append(listener); listener.start(queue: .main)
            }
            return true
        } catch { stop(); return false }
    }
    func stop() {
        let old = listeners; listeners = []; old.forEach { $0.cancel() }
        resetConnections()
    }
    private func resetConnections() {
        let oldCable = cable, oldLocal = local
        cable = nil; local = nil; cableReady = false; localReady = false; pumping = false
        oldCable?.cancel(); oldLocal?.cancel()
    }
    private func accept(_ connection: NWConnection, cable isCable: Bool) {
        guard !listeners.isEmpty, (isCable ? cable : local) == nil else { connection.cancel(); return }
        if isCable { cable = connection } else { local = connection }
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection, connection === (isCable ? self.cable : self.local) else { return }
                switch state {
                case .ready:
                    if isCable { self.cableReady = true } else { self.localReady = true }
                    if self.cableReady && self.localReady && !self.pumping, let cable = self.cable, let local = self.local {
                        self.pumping = true; self.pipe(cable, into: local); self.pipe(local, into: cable)
                    }
                case .failed, .cancelled: self.resetConnections()
                default: break
                }
            }
        }
        connection.start(queue: .main)
    }
    private func pipe(_ source: NWConnection, into destination: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self, weak source, weak destination] data, _, complete, error in
            Task { @MainActor [weak self, weak source, weak destination] in
                guard let self, let source, let destination, self.pumping,
                      (source === self.cable || source === self.local), (destination === self.cable || destination === self.local) else { return }
                guard error == nil, let data, !data.isEmpty else { self.resetConnections(); return }
                // One bounded chunk in flight per direction: slow USB cannot grow an unbounded queue.
                destination.send(content: data, completion: .contentProcessed { [weak self, weak source, weak destination] error in
                    Task { @MainActor [weak self, weak source, weak destination] in
                        guard let self, let source, let destination, self.pumping,
                              (source === self.cable || source === self.local), (destination === self.cable || destination === self.local) else { return }
                        if complete || error != nil { self.resetConnections() } else { self.pipe(source, into: destination) }
                    }
                })
            }
        }
    }
}
