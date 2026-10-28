import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// One Console device has one Relay socket. Release on close/crash, not by trusting a stale PID file.
final class ConsoleRelayProcessLease: @unchecked Sendable {
    private let mutex = NSLock()
    private var descriptor: Int32
    private init(descriptor: Int32) { self.descriptor = descriptor }

    static func acquire(workspaceRoot: URL) throws -> ConsoleRelayProcessLease? {
        #if canImport(Darwin) || canImport(Glibc)
        let directory = workspaceRoot.appendingPathComponent(".sloppy", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = directory.appendingPathComponent("console-relay.lock").path
        let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let code = errno
            _ = close(fd)
            if code == EWOULDBLOCK || code == EAGAIN { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return ConsoleRelayProcessLease(descriptor: fd)
        #else
        throw CocoaError(.featureUnsupported)
        #endif
    }

    func release() {
        mutex.lock(); defer { mutex.unlock() }
        guard descriptor >= 0 else { return }
        #if canImport(Darwin) || canImport(Glibc)
        _ = close(descriptor)
        #endif
        descriptor = -1
    }
    deinit { release() }
}
