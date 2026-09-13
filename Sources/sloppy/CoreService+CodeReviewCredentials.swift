import Foundation
#if canImport(Security)
import Security
#endif
import Protocols

extension CoreService {
    public func codeReviewCredentialStatus(providerID: String) -> CodeReviewCredentialStatus {
        CodeReviewCredentialStatus(
            providerId: providerID,
            isConfigured: codeReviewCredential(providerID: providerID) != nil
        )
    }

    public func saveCodeReviewCredential(providerID: String, token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ChannelPluginError.invalidPayload }
        #if canImport(Security)
        let query = codeReviewCredentialQuery(providerID: providerID)
        SecItemDelete(query as CFDictionary)
        var value = query
        value[kSecValueData as String] = Data(trimmed.utf8)
        value[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(value as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        #else
        throw ChannelPluginError.invalidPayload
        #endif
    }

    public func deleteCodeReviewCredential(providerID: String) throws {
        #if canImport(Security)
        let status = SecItemDelete(codeReviewCredentialQuery(providerID: providerID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        #endif
    }

    func codeReviewCredential(providerID: String) -> String? {
        #if canImport(Security)
        var query = codeReviewCredentialQuery(providerID: providerID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else { return nil }
        return token
        #else
        return nil
        #endif
    }

    #if canImport(Security)
    private func codeReviewCredentialQuery(providerID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "sloppy.code-review",
            kSecAttrAccount as String: providerID,
        ]
    }
    #endif
}
