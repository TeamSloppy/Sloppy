import Foundation
#if canImport(Security)
import Security
import LocalAuthentication
#endif

/// Core has no foreground authorization flow. Credential access must never wait for a dialog.
enum CoreKeychain {
    static func disableInteraction() throws {
        #if os(macOS)
        try check(interactionPolicyStatus)
        #endif
    }

    struct AccessError: LocalizedError {
        let status: Int32

        var errorDescription: String? {
            "Sloppy could not access the saved credential in macOS Keychain. Unlock the login keychain and allow access for the current Sloppy executable in Keychain Access, then retry."
        }
    }

    #if canImport(Security)
    #if os(macOS)
    // LAContext only controls the data-protection keychain. Existing login-keychain
    // items use the file-based implementation, which requires this legacy API.
    // This is process-wide: never temporarily restore it around concurrent requests.
    private static let interactionPolicyStatus = SecKeychainSetUserInteractionAllowed(false)
    #endif

    static func read(query: [String: Any]) throws -> Data? {
        var query = try noninteractive(query)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data else { throw AccessError(status: errSecDecode) }
        return data
    }

    static func save(_ data: Data, query: [String: Any]) throws {
        let query = try noninteractive(query)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var value = query
            value[kSecValueData as String] = data
            try check(SecItemAdd(value as CFDictionary, nil))
        } else {
            // An inaccessible item must not be deleted or replaced with a new credential.
            try check(status)
        }
    }

    static func delete(query: [String: Any]) throws {
        let query = try noninteractive(query)
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private static func noninteractive(_ query: [String: Any]) throws -> [String: Any] {
        try disableInteraction()
        var query = query
        let authentication = LAContext()
        authentication.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = authentication
        return query
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw AccessError(status: status) }
    }
    #endif
}
