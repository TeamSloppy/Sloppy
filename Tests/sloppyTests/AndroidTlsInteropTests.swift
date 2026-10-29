import Foundation
import SloppyRemoteProtocol
import SloppyConsoleProtocol
import Testing
#if canImport(Darwin)
import Darwin

/// Opt-in test peer for the Android protocol tests. Only synthetic identities, on loopback.
@Test(.enabled(if: ProcessInfo.processInfo.environment["SLOPPY_ANDROID_TLS_DIR"] != nil))
func androidTlsPeerFixture() async throws {
    let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SLOPPY_ANDROID_TLS_DIR"]!)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let listener = socket(AF_INET, SOCK_STREAM, 0)
    #expect(listener >= 0)
    defer { Darwin.close(listener) }
    var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = inet_addr("127.0.0.1"); address.sin_port = 0
    let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    #expect(bound == 0 && Darwin.listen(listener, 1) == 0)
    var size = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &size) } }
    let identity = try RemoteTLSIdentity(signingPrivateKey: Data(repeating: 17, count: 32), deviceID: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!)
    let rejectPin = ProcessInfo.processInfo.environment["SLOPPY_ANDROID_TLS_REJECT_PIN"] == "1"
    let rpc = ProcessInfo.processInfo.environment["SLOPPY_ANDROID_TLS_RPC"] == "1"
    let metadata: [String: Any] = ["port": Int(UInt16(bigEndian: address.sin_port)), "certificate": identity.certificateDER.base64EncodedString(), "rejectPin": rejectPin, "rpc": rpc]
    try JSONSerialization.data(withJSONObject: metadata).write(to: directory.appendingPathComponent("peer.json"), options: .atomic)
    var pollState = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
    guard Darwin.poll(&pollState, 1, 60_000) > 0 else { Issue.record("Android peer did not connect"); return }
    let client = accept(listener, nil, nil); #expect(client >= 0)
    defer { Darwin.close(client) }
    var noSigpipe: Int32 = 1
    _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, socklen_t(MemoryLayout<Int32>.size))
    var timeout = timeval(tv_sec: 15, tv_usec: 0)
    _ = setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    func readExact(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count); var offset = 0
        while offset < count {
            let result = bytes.withUnsafeMutableBytes { Darwin.read(client, $0.baseAddress!.advanced(by: offset), count - offset) }
            guard result > 0 else { throw CocoaError(.fileReadUnknown) }; offset += result
        }
        return Data(bytes)
    }
    func readFrame() throws -> Data {
        let header = try readExact(4), length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length <= 4 * 1024 * 1024 + 65_536 else { throw CocoaError(.fileReadTooLarge) }
        return try readExact(Int(length))
    }
    func writeFrame(_ bytes: Data) throws {
        var length = UInt32(bytes.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }; frame.append(bytes)
        var offset = 0
        while offset < frame.count {
            let result = frame.withUnsafeBytes { Darwin.write(client, $0.baseAddress!.advanced(by: offset), frame.count - offset) }
            guard result > 0 else { throw CocoaError(.fileWriteUnknown) }; offset += result
        }
    }
    let certificate = try readFrame()
    let tls = try await RemoteTLSChannel(identity: identity, peerCertificate: certificate, isClient: false)
    var echoed = false
    do {
    for _ in 0..<30 {
        let flight = try await tls.receive(readFrame())
        var output = flight.records.reduce(into: Data()) { $0.append($1) }
        for message in flight.messages {
            #expect(flight.handshakeComplete)
            var response = message
            if rpc {
                let packet = try ConsoleWire.decode(ConsoleRemotePacket.self, from: message)
                let request = try ConsoleWire.decode(RemoteCoreRequest.self, from: packet.payload)
                #expect(packet.kind == "core.http" && request.method == "POST" && request.path == "/v1/agents/fixture/sessions/test/messages")
                let body = try JSONSerialization.jsonObject(with: #require(request.body)) as? [String: Any]
                #expect(body?["content"] as? String == "Hello from Android")
                response = try ConsoleWire.encode(ConsoleRemotePacket(kind: "core.http.response", payload: ConsoleWire.encode(RemoteCoreResponse(requestID: request.requestID, status: 200, body: Data("{\"accepted\":true}".utf8)))))
            } else { #expect(message.count == 200_000) }
            let reply = try await tls.send(response)
            output.append(reply.records.reduce(into: Data()) { $0.append($1) })
            echoed = true
        }
        try writeFrame(output)
        if echoed { break }
    }
    } catch {
        if !rejectPin { throw error }
    }
    #expect(echoed != rejectPin)
    await tls.close()
}
#endif
