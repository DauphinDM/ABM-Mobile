import Foundation
import CryptoKit

// A bounded wire format shared with the Qt Android client, not arbitrary RPC.
enum JSONValue: Codable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    subscript(_ key: String) -> JSONValue { object[key] ?? .null }
    var object: [String: JSONValue] { if case .object(let v) = self { return v }; return [:] }
    var array: [JSONValue] { if case .array(let v) = self { return v }; return [] }
    var text: String { if case .string(let v) = self { return v }; return "" }
    var number: Double? { if case .number(let v) = self { return v }; return nil }
    var flag: Bool { self == .bool(true) }
    var display: String {
        if case .number(let v) = self { return v.formatted(.number.precision(.fractionLength(0...2))) }
        return text.isEmpty ? "—" : text
    }
}

struct Invitation: Decodable {
    let v: Int
    let host: String
    let port: UInt16
    let sha256: String
    let secret: String
    let transport: String?

    static func parse(_ link: String) throws -> Invitation {
        guard link.utf8.count <= 2048, link.hasPrefix("abm://pair/") else { throw WireError.invitation }
        let payload = String(link.dropFirst(11))
        guard !payload.isEmpty, payload.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { throw WireError.invitation }
        var base64 = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let bytes = Data(base64Encoded: base64) else { throw WireError.invitation }
        let value = try JSONDecoder().decode(Invitation.self, from: bytes)
        guard value.v == 1, value.port > 0, privateIPv4(value.host), hex(value.sha256), hex(value.secret) else { throw WireError.invitation }
        return value
    }
    static func privateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let bytes = parts.compactMap { part -> UInt8? in
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), part.count <= 3,
                  part.count == 1 || part.first != "0" else { return nil }
            return UInt8(part)
        }
        guard bytes.count == 4 else { return false }
        return bytes[0] == 10 || bytes[0] == 127 || (bytes[0] == 192 && bytes[1] == 168) || (bytes[0] == 172 && (16...31).contains(bytes[1]))
    }
    static func hex(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

enum WireError: Error { case invitation, size, response }

struct LineDecoder {
    private var buffer = Data()
    mutating func append(_ data: Data) throws -> [JSONValue] {
        guard buffer.count + data.count <= 2 * 1024 * 1024 else { throw WireError.size }
        buffer.append(data)
        var lines: [JSONValue] = []
        while let end = buffer.firstIndex(of: 10) {
            let value = try JSONDecoder().decode(JSONValue.self, from: buffer[..<end])
            guard case .object = value else { throw WireError.response }
            lines.append(value)
            buffer.removeSubrange(...end)
        }
        return lines
    }
}

enum CompanionWire {
    static let workshopActions = ["power","rpm","clutch","persistence","handling","engine","gears","gravity","deformation","dimensions","repair","ignite","extinguish","deflate","stability","dealer","dealerStop","fullReset","presetSave","presetApply","presetCancel"]
    static func workshopAvailable(_ action: String, state: JSONValue) -> Bool {
        let extended = ["gravity","deformation","dimensions","ignite","deflate","dealer","presetSave","presetApply","presetCancel"]
        return !extended.contains(action) || (state["remoteWorkshop"]["version"].number ?? 0) >= 2
    }
    static func certificateMatches(_ data: Data, pin: String) -> Bool {
        Invitation.hex(pin) && SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == pin
    }
    static func mutable(_ state: JSONValue, connected: Bool, busy: Bool) -> Bool {
        guard let speed = state["telemetry"]["speed"].number, speed.isFinite, speed >= 0, speed <= 1 else { return false }
        return connected && !busy && state["connected"].flag && state["controlsAvailable"].flag && state["vehicleOwned"].flag
            && state["sandboxAllowed"].flag && !state["joining"].flag && !state["policyCleanup"].flag
    }
    static func spawnable(_ state: JSONValue, connected: Bool, busy: Bool) -> Bool {
        guard connected, !busy, state["connected"].flag, state["controlsAvailable"].flag, state["sandboxAllowed"].flag,
              !state["joining"].flag, !state["policyCleanup"].flag, !state["map"].text.isEmpty else { return false }
        return state["vehicleId"] == .null || mutable(state, connected: connected, busy: busy)
    }
    static func serverAddress(_ state: JSONValue) -> String {
        let host = state["serverIp"].text
        guard !host.isEmpty, let port = state["serverPort"].number, port >= 1, port <= 65535, port.rounded() == port else { return "" }
        return "\(host.contains(":") ? "[\(host)]" : host):\(Int(port))"
    }
}

enum WorkshopRules {
    static func number(_ text: String, range: ClosedRange<Double>) -> Double? {
        guard let value=Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite, range.contains(value) else { return nil }
        return value
    }
    static func ratios(_ text: String) -> [Double]? {
        guard text.utf8.count <= 24000 else { return nil }
        let pieces=text.components(separatedBy: CharacterSet(charactersIn: ",; \t\n\r")).filter { !$0.isEmpty }
        let values=pieces.compactMap { number($0,range: 0.01...100) }
        return !pieces.isEmpty && values.count==pieces.count ? values : nil
    }
    static func nextRatio(_ text: String) -> Double? {
        guard let values=ratios(text), values.count>=2 else { return nil }
        let factors=(max(1,values.count-3)..<values.count).compactMap { index -> Double? in
            let value=values[index]/values[index-1]; return value>0 && value<1 ? value : nil
        }.sorted()
        guard !factors.isEmpty, let last=values.last else { return nil }
        let middle=factors.count/2
        let retention=factors.count%2==0 ? (factors[middle-1]+factors[middle])/2 : factors[middle]
        let value=(last*retention*10000).rounded()/10000
        return (0.01...100).contains(value) ? value : nil
    }
    static func rpmRange(_ workshop: JSONValue) -> ClosedRange<Double>? {
        let engines=workshop["engines"].array
        guard !engines.isEmpty else { return nil }
        let low=engines.reduce(100.0) { max($0,($1["idleRPM"].number ?? 0)+100) }
        let high=engines.reduce(30000.0) { min($0,$1["rpmCeiling"].number ?? 0) }
        return high>=low ? low...high : nil
    }
}
