import Foundation
import Protocols
import SloppyNodeCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif os(Windows)
import WinSDK
#endif

struct CoreLocalClientCredential: Codable, Sendable {
    var version = 1
    var baseURL: URL
    var token: String

    static func isLoopbackAddress(_ address: String?) -> Bool {
        guard let address else { return false }
        let host = address.lowercased()
        if host == "::1" || host == "::ffff:127.0.0.1" { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.first == "127" && parts.allSatisfy { UInt8($0) != nil }
    }

    func matches(_ candidate: String) -> Bool {
        let lhs = Array(token.utf8), rhs = Array(candidate.utf8)
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

extension CoreService {
    func publishLocalClientCredential(port: Int, fileURL: URL) throws {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = port
        guard let baseURL = components.url else { throw CoreIdentityAuthError.invalidCredentials }
        let credential = CoreLocalClientCredential(
            baseURL: baseURL, token: "slp_local_" + NodeIdentityGenerator.randomToken(byteCount: 32)
        )
        let directory = fileURL.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".local-client-" + UUID().uuidString)
        let fileManager = FileManager.default
        #if os(Windows)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeWindowsLocalCredential(try JSONEncoder().encode(credential), temporary: temporary, destination: fileURL)
        #else
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        defer { try? fileManager.removeItem(at: temporary) }
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.write(contentsOf: JSONEncoder().encode(credential))
        try handle.close()
        guard rename(temporary.path, fileURL.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        #endif
        localClientCredential = credential
    }

    func exchangeLocalClientCredential(_ authorization: String?) async throws -> AuthSessionResponse {
        guard let credential = localClientCredential,
              let authorization, authorization.hasPrefix("Bearer "),
              credential.matches(String(authorization.dropFirst(7))) else {
            throw CoreIdentityAuthError.invalidCredentials
        }
        guard await identityAuthChallenge().mode == .loginPassword else {
            throw CoreIdentityAuthError.disabled
        }
        return try await identityAuthService.makeLocalOwnerSession()
    }
}

#if os(Windows)
private func writeWindowsLocalCredential(_ data: Data, temporary: URL, destination: URL) throws {
    defer { try? FileManager.default.removeItem(at: temporary) }
    // Protect the token at creation time, including when the workspace has an inherited public ACL.
    var descriptor: PSECURITY_DESCRIPTOR?
    let converted = "D:P(A;;FA;;;OW)".withCString(encodedAs: UTF16.self) {
        ConvertStringSecurityDescriptorToSecurityDescriptorW($0, DWORD(SDDL_REVISION_1), &descriptor, nil)
    }
    guard converted, let descriptor else { throw CocoaError(.fileWriteNoPermission) }
    defer { _ = LocalFree(descriptor) }
    var security = SECURITY_ATTRIBUTES(nLength: DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size),
                                       lpSecurityDescriptor: descriptor, bInheritHandle: false)
    let handle = temporary.path.withCString(encodedAs: UTF16.self) {
        CreateFileW($0, DWORD(GENERIC_WRITE), 0, &security, DWORD(CREATE_NEW), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
    }
    guard let handle, handle != INVALID_HANDLE_VALUE else { throw CocoaError(.fileWriteUnknown) }
    var closed = false
    defer { if !closed { _ = CloseHandle(handle) } }
    var written: DWORD = 0
    let success = data.withUnsafeBytes { WriteFile(handle, $0.baseAddress, DWORD($0.count), &written, nil) }
    guard success, written == data.count, FlushFileBuffers(handle) else { throw CocoaError(.fileWriteUnknown) }
    // Close before renaming: Windows does not allow a rename without FILE_SHARE_DELETE.
    guard CloseHandle(handle) else { throw CocoaError(.fileWriteUnknown) }
    closed = true
    let moved = temporary.path.withCString(encodedAs: UTF16.self) { source in
        destination.path.withCString(encodedAs: UTF16.self) {
            MoveFileExW(source, $0, DWORD(MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
        }
    }
    guard moved else { throw CocoaError(.fileWriteUnknown) }
}
#endif
