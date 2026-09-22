import Foundation

enum TLSCertificateFingerprintProbeError: LocalizedError, Sendable {
    case invalidURL
    case opensslUnavailable
    case timedOut
    case certificateMissing(String)
    case certificateConversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The public client URL must be an HTTPS URL without a path."
        case .opensslUnavailable:
            return "OpenSSL is unavailable on the Sloppy host. Install openssl and retry."
        case .timedOut:
            return "The TLS connection timed out. Check the public URL and firewall."
        case .certificateMissing(let detail):
            return "The endpoint did not return a TLS certificate. \(detail)"
        case .certificateConversionFailed(let detail):
            return "OpenSSL could not decode the endpoint certificate. \(detail)"
        }
    }
}

enum TLSCertificateFingerprintProbe {
    static func fingerprint(for url: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            try fingerprintSynchronously(for: url)
        }.value
    }

    static func firstCertificatePEM(in output: String) -> String? {
        let beginMarker = "-----BEGIN CERTIFICATE-----"
        let endMarker = "-----END CERTIFICATE-----"
        guard let begin = output.range(of: beginMarker),
              let end = output.range(of: endMarker, range: begin.lowerBound..<output.endIndex) else {
            return nil
        }
        return String(output[begin.lowerBound..<end.upperBound]) + "\n"
    }

    private static func fingerprintSynchronously(for url: URL) throws -> String {
        guard url.scheme?.lowercased() == "https",
              let host = url.host,
              url.path.isEmpty || url.path == "/" else {
            throw TLSCertificateFingerprintProbeError.invalidURL
        }
        let authority = host.contains(":") ? "[\(host)]:\(url.port ?? 443)" : "\(host):\(url.port ?? 443)"
        let handshake = try runOpenSSL(
            arguments: ["s_client", "-connect", authority, "-servername", host, "-showcerts"],
            input: Data(),
            timeout: 12
        )
        guard !handshake.timedOut else {
            throw TLSCertificateFingerprintProbeError.timedOut
        }
        if handshake.exitCode == 127 {
            throw TLSCertificateFingerprintProbeError.opensslUnavailable
        }
        let handshakeText = String(decoding: handshake.stdout, as: UTF8.self)
        guard let pem = firstCertificatePEM(in: handshakeText) else {
            throw TLSCertificateFingerprintProbeError.certificateMissing(handshake.errorDetail)
        }
        let conversion = try runOpenSSL(
            arguments: ["x509", "-outform", "DER"],
            input: Data(pem.utf8),
            timeout: 5
        )
        guard !conversion.timedOut else {
            throw TLSCertificateFingerprintProbeError.timedOut
        }
        guard conversion.exitCode == 0, !conversion.stdout.isEmpty else {
            throw TLSCertificateFingerprintProbeError.certificateConversionFailed(conversion.errorDetail)
        }
        return TaskSyncCrypto.sha256Hex(conversion.stdout)
    }

    private struct ProcessResult {
        var exitCode: Int32
        var stdout: Data
        var stderr: Data
        var timedOut: Bool

        var errorDetail: String {
            let value = String(decoding: stderr, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? "" : String(value.prefix(500))
        }
    }

    private static func runOpenSSL(
        arguments: [String],
        input: Data,
        timeout: TimeInterval
    ) throws -> ProcessResult {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/env") else {
            throw TLSCertificateFingerprintProbeError.opensslUnavailable
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["openssl"] + arguments
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw TLSCertificateFingerprintProbeError.opensslUnavailable
        }
        try stdin.fileHandleForWriting.write(contentsOf: input)
        try? stdin.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        let timedOut = process.isRunning
        if timedOut {
            process.terminate()
        }
        process.waitUntilExit()
        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr: stderr.fileHandleForReading.readDataToEndOfFile(),
            timedOut: timedOut
        )
    }
}
