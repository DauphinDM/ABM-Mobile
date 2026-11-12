import XCTest
import CryptoKit
import Network
@testable import ABMMobile

final class ProtocolTests: XCTestCase {
    private func link(host: String = "192.168.1.20", port: JSONValue = .number(44445), version: JSONValue = .number(1)) throws -> String {
        let payload: JSONValue = .object(["v": version, "host": .string(host), "port": port, "sha256": .string(String(repeating: "a", count: 64)), "secret": .string(String(repeating: "b", count: 64))])
        return "abm://pair/" + (try JSONEncoder().encode(payload)).base64EncodedString().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    }
    func testPrivateInvitationsAreStrictlyBounded() throws {
        for ip in ["10.0.0.1", "172.16.0.1", "172.31.255.254", "192.168.1.20", "127.0.0.1"] {
            XCTAssertEqual(try Invitation.parse(link(host: ip)).host, ip)
        }
        for ip in ["8.8.8.8", "0.0.0.0", "192.168.0.256", "172.32.0.1", "localhost", "::1", "192.168.01.1", "10.0.0.1.evil", "10.0.0.1\n"] {
            XCTAssertThrowsError(try Invitation.parse(link(host: ip)), ip)
        }
        XCTAssertThrowsError(try Invitation.parse(link(port: .number(0))))
        XCTAssertThrowsError(try Invitation.parse(link(port: .number(1.5))))
        XCTAssertThrowsError(try Invitation.parse(link(version: .number(2))))
        XCTAssertThrowsError(try Invitation.parse("abm://pair/" + String(repeating: "a", count: 2048)))
        XCTAssertThrowsError(try Invitation.parse("https://example.com"))
        XCTAssertThrowsError(try Invitation.parse("abm://pair/!!!!"))
    }
    func testCertificatePinIsExact() {
        let cert = Data("test certificate".utf8)
        let pin = SHA256.hash(data: cert).map { String(format: "%02x", $0) }.joined()
        XCTAssertTrue(CompanionWire.certificateMatches(cert, pin: pin))
        XCTAssertFalse(CompanionWire.certificateMatches(Data("different".utf8), pin: pin))
        XCTAssertFalse(CompanionWire.certificateMatches(cert, pin: pin.uppercased()))
    }
    func testFramingRejectsInvalidAndOversizedResponses() throws {
        var parser = LineDecoder()
        XCTAssertTrue(try parser.append(Data("{\"kind\":".utf8)).isEmpty)
        let values = try parser.append(Data("\"ready\"}\n{\"kind\":\"pending\"}\n".utf8))
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(values[0]["kind"].text, "ready")
        XCTAssertThrowsError(try parser.append(Data("[]\n".utf8)))
        var bounded = LineDecoder()
        XCTAssertThrowsError(try bounded.append(Data(repeating: 65, count: 2 * 1024 * 1024 + 1)))
    }
    func testPolicyMovementAndIdentityTypesFailClosed() {
        var fields: [String: JSONValue] = ["connected": .bool(true), "controlsAvailable": .bool(true), "vehicleOwned": .bool(true), "sandboxAllowed": .bool(true), "telemetry": .object(["speed": .number(0)])]
        XCTAssertTrue(CompanionWire.mutable(.object(fields), connected: true, busy: false))
        XCTAssertFalse(CompanionWire.mutable(.object(fields), connected: false, busy: false))
        XCTAssertFalse(CompanionWire.mutable(.object(fields), connected: true, busy: true))
        for key in ["controlsAvailable", "vehicleOwned", "sandboxAllowed", "connected"] {
            var denied = fields; denied[key] = .bool(false)
            XCTAssertFalse(CompanionWire.mutable(.object(denied), connected: true, busy: false))
        }
        for key in ["joining", "policyCleanup"] {
            var denied = fields; denied[key] = .bool(true)
            XCTAssertFalse(CompanionWire.mutable(.object(denied), connected: true, busy: false))
        }
        for speed in [JSONValue.null, .string("0"), .number(2), .number(-1)] {
            fields["telemetry"] = .object(["speed": speed])
            XCTAssertFalse(CompanionWire.mutable(.object(fields), connected: true, busy: false))
        }
        XCTAssertEqual(CompanionWire.serverAddress(.object(["serverIp": .string("2001:db8::7"), "serverPort": .number(30814)])), "[2001:db8::7]:30814")
    }
    func testSpawnIntoEmptyMapDoesNotRequireAnExistingVehicle() {
        var fields: [String: JSONValue] = ["connected": .bool(true), "controlsAvailable": .bool(true), "sandboxAllowed": .bool(true), "map": .string("gridmap_v2")]
        XCTAssertTrue(CompanionWire.spawnable(.object(fields), connected: true, busy: false))
        XCTAssertFalse(CompanionWire.mutable(.object(fields), connected: true, busy: false))
        for key in ["sandboxAllowed", "controlsAvailable", "connected"] {
            var blocked = fields; blocked[key] = .bool(false)
            XCTAssertFalse(CompanionWire.spawnable(.object(blocked), connected: true, busy: false))
        }
        fields["vehicleId"] = .number(42)
        XCTAssertFalse(CompanionWire.spawnable(.object(fields), connected: true, busy: false))
        fields["vehicleOwned"] = .bool(true); fields["telemetry"] = .object(["speed": .number(0)])
        XCTAssertTrue(CompanionWire.spawnable(.object(fields), connected: true, busy: false))
        fields["telemetry"] = .object(["speed": .number(3)])
        XCTAssertFalse(CompanionWire.spawnable(.object(fields), connected: true, busy: false))
    }
    @MainActor func testUsbRelayCarriesBytesBothWaysAndStops() async throws {
        let relay = USBRelay(); XCTAssertTrue(relay.start())
        let cable = NWConnection(host: "127.0.0.1", port: 44446, using: .tcp)
        let local = NWConnection(host: "127.0.0.1", port: 44447, using: .tcp)
        defer { cable.cancel(); local.cancel(); relay.stop() }
        let ready = expectation(description: "Both loopback connections ready"); ready.expectedFulfillmentCount = 2
        for connection in [cable, local] {
            connection.stateUpdateHandler = { state in if case .ready = state { ready.fulfill() } }
            connection.start(queue: .main)
        }
        await fulfillment(of: [ready], timeout: 5)
        let forward = expectation(description: "TLS bytes are not interpreted")
        let backward = expectation(description: "Reply bytes reach cable")
        local.receive(minimumIncompleteLength: 5, maximumLength: 5) { data, _, _, error in
            XCTAssertNil(error); XCTAssertEqual(data, Data([22,3,3,0,0])); forward.fulfill()
        }
        cable.receive(minimumIncompleteLength: 4, maximumLength: 4) { data, _, _, error in
            XCTAssertNil(error); XCTAssertEqual(data, Data("pong".utf8)); backward.fulfill()
        }
        cable.send(content: Data([22,3,3,0,0]), completion: .contentProcessed { XCTAssertNil($0) })
        local.send(content: Data("pong".utf8), completion: .contentProcessed { XCTAssertNil($0) })
        await fulfillment(of: [forward, backward], timeout: 5)
    }
    func testRememberedPCUsesAnIsolatedKeychainRecordAndCanBeRevoked() {
        let account = "test-" + UUID().uuidString
        defer { _ = RememberedPC.forget(account: account) }
        let pc = RememberedPC(host: "192.168.1.20", port: 44445, pin: String(repeating: "a", count: 64), id: String(repeating: "b", count: 32), token: String(repeating: "c", count: 64), name: "Test phone")
        XCTAssertNil(RememberedPC.load(account: account))
        XCTAssertTrue(pc.save(account: account))
        XCTAssertEqual(RememberedPC.load(account: account)?.token, pc.token)
        XCTAssertTrue(RememberedPC.forget(account: account))
        XCTAssertNil(RememberedPC.load(account: account))
    }
    @MainActor func testNoOfflineCommandQueue() {
        let client = CompanionClient()
        client.command("repair")
        XCTAssertFalse(client.connected)
        XCTAssertFalse(client.canChange)
        XCTAssertEqual(client.state, .null)
        XCTAssertTrue(client.message.contains("Nothing was queued"))
        client.pair(link: "invalid", device: "My phone")
        XCTAssertFalse(client.connected)
    }
}
