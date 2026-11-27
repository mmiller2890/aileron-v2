import Foundation
import Security

public protocol SecretStore: Sendable {
    func setSecret(_ value: String, for account: String) throws
    func secret(for account: String) -> String?
    func deleteSecret(for account: String) throws
    func hasSecret(for account: String) -> Bool
}

public enum KeychainStoreError: LocalizedError {
    case encodingFailed
    case osStatus(OSStatus)
    case readbackMismatch

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Could not encode secret for macOS Keychain."
        case .osStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "macOS Keychain operation failed: \(message)"
        case .readbackMismatch:
            return "macOS Keychain write succeeded but readback verification failed."
        }
    }
}

public final class KeychainStore: SecretStore, @unchecked Sendable {
    private let service: String

    public init(service: String = "com.aileron.macos.secrets") {
        self.service = service
    }

    public func setSecret(_ value: String, for account: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try deleteSecret(for: account)
            return
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw KeychainStoreError.encodingFailed
        }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainStoreError.osStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainStoreError.osStatus(updateStatus)
        }

        guard hasSecret(for: account) else {
            throw KeychainStoreError.readbackMismatch
        }
    }

    public func secret(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    public func deleteSecret(for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.osStatus(status)
        }
    }

    public func hasSecret(for account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }
}
