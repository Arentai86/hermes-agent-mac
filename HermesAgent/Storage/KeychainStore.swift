import Foundation
import Security

#if canImport(KeychainAccess)
import KeychainAccess
#endif

struct KeychainStore {
    private let service = "com.hermes.app"

    func set(_ value: String, for key: String) throws {
        guard !value.isEmpty else { return }
        #if canImport(KeychainAccess)
        try Keychain(service: service)
            .accessibility(.afterFirstUnlockThisDeviceOnly)
            .set(value, key: key)
        #else
        try setWithSecurityFramework(value, for: key)
        #endif
    }

    func get(_ key: String) throws -> String? {
        #if canImport(KeychainAccess)
        return try Keychain(service: service).get(key)
        #else
        return try getWithSecurityFramework(key)
        #endif
    }

    func remove(_ key: String) throws {
        #if canImport(KeychainAccess)
        try Keychain(service: service).remove(key)
        #else
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
        #endif
    }

    func removeAllKnownItems(keys: [String]) {
        for key in keys {
            try? remove(key)
        }
    }

    private func setWithSecurityFramework(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(for: key)
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        case errSecInteractionNotAllowed:
            throw KeychainError.interactionNotAllowed
        default:
            throw KeychainError.status(updateStatus)
        }
    }

    private func getWithSecurityFramework(_ key: String) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw KeychainError.invalidData }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed:
            throw KeychainError.interactionNotAllowed
        default:
            throw KeychainError.status(status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }
}

enum KeychainError: LocalizedError {
    case status(OSStatus)
    case interactionNotAllowed
    case invalidData

    var errorDescription: String? {
        switch self {
        case let .status(status):
            return "Keychain operation failed with status \(status)."
        case .interactionNotAllowed:
            return "Keychain is locked or user interaction is not allowed right now."
        case .invalidData:
            return "Keychain item data is not valid UTF-8 text."
        }
    }
}
