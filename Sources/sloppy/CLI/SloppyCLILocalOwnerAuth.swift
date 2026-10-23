import Foundation
import Protocols
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Uses the same private, loopback-only owner exchange as the native client.
enum SloppyCLILocalOwnerAuth {
    static func load(_ fileURL: URL, for baseURL: URL) -> CoreLocalClientCredential? {
        guard isLocalEndpoint(baseURL) else { return nil }
        #if canImport(Darwin) || canImport(Glibc)
        // Open without following symlinks and validate the descriptor we actually read.
        let descriptor = open(fileURL.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_uid == geteuid(), metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_mode & 0o077 == 0, metadata.st_size <= 16_384,
              let data = try? handle.readToEnd(),
              let credential = try? JSONDecoder().decode(CoreLocalClientCredential.self, from: data),
              credential.version == 1, credential.token.hasPrefix("slp_local_"),
              credential.token.count >= 40, isLocalEndpoint(credential.baseURL),
              (credential.baseURL.port ?? 80) == (baseURL.port ?? 80) else { return nil }
        return credential
        #else
        // Platforms without POSIX ownership checks retain explicit/session authentication.
        return nil
        #endif
    }

    static func isLocalEndpoint(_ url: URL) -> Bool {
        let host = url.host?.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return url.scheme == "http" && CoreLocalClientCredential.isLoopbackAddress(host)
            && url.user == nil && url.password == nil
            && (url.path.isEmpty || url.path == "/") && url.query == nil && url.fragment == nil
    }

    static func exchange(_ credential: CoreLocalClientCredential) async throws -> AuthSessionResponse {
        guard isLocalEndpoint(credential.baseURL) else { throw CLIClientError.invalidURL }
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: credential.baseURL.appendingPathComponent("v1/auth/local-session"), timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer " + credential.token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CLIClientError.noData }
        guard http.statusCode == 200 else {
            throw CLIClientError.httpError(http.statusCode, "Local owner sign-in failed; run `sloppy auth login`.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(AuthSessionResponse.self, from: data)
        guard !result.accessToken.isEmpty, !result.refreshToken.isEmpty else { throw CLIClientError.noData }
        // Neither the bootstrap secret nor the ephemeral session is written into a project.
        return result
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
