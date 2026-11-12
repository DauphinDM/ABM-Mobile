import Foundation
import Security

struct RememberedPC: Codable {
    var host: String
    var port: UInt16
    var pin: String
    var id: String
    var token: String
    var name: String
    var usb: Bool? = nil

    private static var service: String { (Bundle.main.bundleIdentifier ?? "ABMMobile") + ".remembered-pc" }
    static func load(account: String = "pc") -> RememberedPC? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              data.count <= 4096, let pc = try? JSONDecoder().decode(Self.self, from: data),
              Invitation.privateIPv4(pc.host), pc.port > 0, Invitation.hex(pc.pin), Invitation.hex(pc.token),
              pc.id.count == 32, pc.id.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { return nil }
        return pc
    }
    func save(account: String = "pc") -> Bool {
        saveStatus(account: account) == errSecSuccess
    }
    func saveStatus(account: String = "pc") -> OSStatus {
        guard let data = try? JSONEncoder().encode(self) else { return errSecParam }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: account]
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return status }
        guard status == errSecItemNotFound else { return status }
        return SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
    }
    static func forget(account: String = "pc") -> Bool {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
