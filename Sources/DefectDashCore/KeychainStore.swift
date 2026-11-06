import Foundation
import Security

public enum KeychainError: Error, CustomStringConvertible {
    case status(OSStatus)
    case encoding

    public var description: String {
        switch self {
        case let .status(code):
            let message = SecCopyErrorMessageString(code, nil) as String? ?? "unknown"
            return "Keychain error \(code): \(message)"
        case .encoding:
            return "Keychain item is not valid UTF-8"
        }
    }
}

/// Generic-password item in the login keychain. The secret never leaves the Keychain except through `load()`.
public struct KeychainStore: Sendable {
    public let service: String
    public let account: String

    public init(service: String = "io.github.arawn-davies.defectdash", account: String = "asana-pat") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// SecItemAdd; on duplicate, SecItemUpdate.
    public func save(_ secret: String) throws {
        let data = Data(secret.utf8)
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "DefectDash Asana PAT"
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard update == errSecSuccess else { throw KeychainError.status(update) }
            return
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    public func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.encoding
        }
        return string
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}
