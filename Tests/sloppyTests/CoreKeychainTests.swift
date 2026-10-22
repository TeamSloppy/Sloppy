import Foundation
import Testing
@testable import sloppy
#if os(macOS)
import Security

@Suite(.serialized)
struct CoreKeychainTests {
    @Test
    func lockedKeychainFailsWithoutInteractionAndPreservesCredential() throws {
        try CoreKeychain.disableInteraction()
        var interactionAllowed = DarwinBoolean(true)
        #expect(SecKeychainGetUserInteractionAllowed(&interactionAllowed) == errSecSuccess)
        #expect(!interactionAllowed.boolValue)

        // Use a disposable keychain with a known test password, never the login keychain.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let password = Data(UUID().uuidString.utf8)
        var created: SecKeychain?
        let createStatus = password.withUnsafeBytes { bytes in
            SecKeychainCreate(
                directory.appendingPathComponent("test.keychain").path,
                UInt32(bytes.count), bytes.baseAddress, false, nil, &created
            )
        }
        try #require(createStatus == errSecSuccess)
        let keychain = try #require(created)
        defer { SecKeychainDelete(keychain) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "sloppy.keychain-test",
            kSecAttrAccount as String: "test",
            kSecUseKeychain as String: keychain,
            kSecMatchSearchList as String: [keychain],
        ]

        #expect(try CoreKeychain.read(query: query) == nil)
        try CoreKeychain.save(Data("first-test-value".utf8), query: query)
        try CoreKeychain.save(Data("updated-test-value".utf8), query: query)
        #expect(try CoreKeychain.read(query: query) == Data("updated-test-value".utf8))
        try #require(SecKeychainLock(keychain) == errSecSuccess)

        let started = ContinuousClock.now
        for _ in 0..<3 {
            #expect(throws: CoreKeychain.AccessError.self) {
                try CoreKeychain.read(query: query)
            }
        }
        #expect(ContinuousClock.now - started < .seconds(5))
        #expect(throws: CoreKeychain.AccessError.self) {
            try CoreKeychain.save(Data("must-not-replace".utf8), query: query)
        }

        let unlockStatus = password.withUnsafeBytes { bytes in
            SecKeychainUnlock(keychain, UInt32(bytes.count), bytes.baseAddress, true)
        }
        try #require(unlockStatus == errSecSuccess)
        #expect(try CoreKeychain.read(query: query) == Data("updated-test-value".utf8))
        try CoreKeychain.delete(query: query)
        #expect(try CoreKeychain.read(query: query) == nil)
        try CoreKeychain.delete(query: query)
    }
}
#endif
