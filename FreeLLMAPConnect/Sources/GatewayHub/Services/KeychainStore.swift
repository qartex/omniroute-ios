import Foundation
import Security

enum KeychainStore {
    private static let service = "com.qartex.freellmapconnect.gatewayhub"

    static func value(for account: String) -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    @discardableResult
    static func save(_ value: String, for account: String) -> Bool {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var creationQuery = query
            attributes.forEach { creationQuery[$0.key] = $0.value }
            return SecItemAdd(creationQuery as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func delete(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension GatewayCredentials {
    static func load(for instanceID: UUID) -> GatewayCredentials {
        GatewayCredentials(
            managementPassword: KeychainStore.value(for: "\(instanceID.uuidString).managementPassword"),
            apiKey: KeychainStore.value(for: "\(instanceID.uuidString).apiKey")
        )
    }

    func save(for instanceID: UUID) {
        save(managementPassword, account: "\(instanceID.uuidString).managementPassword")
        save(apiKey, account: "\(instanceID.uuidString).apiKey")
    }

    private func save(_ value: String, account: String) {
        if value.isEmpty { KeychainStore.delete(account: account) }
        else { KeychainStore.save(value, for: account) }
    }

    static func delete(for instanceID: UUID) {
        KeychainStore.delete(account: "\(instanceID.uuidString).managementPassword")
        KeychainStore.delete(account: "\(instanceID.uuidString).apiKey")
    }
}
