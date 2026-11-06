import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif os(Windows)
import WinSDK
#endif

/// An OS-held lease. Keep the lock file: unlinking it would permit two different lock inodes.
public final class FileOwnershipLease: @unchecked Sendable {
    public enum LeaseError: Error, Sendable { case owned, unavailable }
    private let mutex = NSLock()
    #if os(Windows)
    private var handle: HANDLE?
    private init(handle: HANDLE) { self.handle = handle }
    #else
    private var descriptor: Int32
    private init(descriptor: Int32) { self.descriptor = descriptor }
    #endif

    public static func acquire(at url: URL) throws -> FileOwnershipLease {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        #if canImport(Darwin) || canImport(Glibc)
        let fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw LeaseError.unavailable }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            _ = close(fd)
            if code == EWOULDBLOCK || code == EAGAIN { throw LeaseError.owned }
            throw LeaseError.unavailable
        }
        return FileOwnershipLease(descriptor: fd)
        #elseif os(Windows)
        let handle = url.path.withCString(encodedAs: UTF16.self) {
            CreateFileW($0, DWORD(GENERIC_READ) | DWORD(GENERIC_WRITE), 0, nil, DWORD(OPEN_ALWAYS),
                DWORD(FILE_ATTRIBUTE_NORMAL) | DWORD(FILE_FLAG_OPEN_REPARSE_POINT), nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else {
            if GetLastError() == DWORD(ERROR_SHARING_VIOLATION) { throw LeaseError.owned }
            throw LeaseError.unavailable
        }
        return FileOwnershipLease(handle: handle)
        #else
        throw LeaseError.unavailable
        #endif
    }

    /// Stores a weak authority reference; each writer retains a live lease for its whole commit.
    /// A stopped owner cannot revive it, while an outstanding factual writer can finish safely.
    public final class Reference: @unchecked Sendable {
        private let mutex = NSLock()
        private weak var lease: FileOwnershipLease?
        public init() {}
        public func bind(_ lease: FileOwnershipLease) {
            mutex.lock(); defer { mutex.unlock() }
            self.lease = lease
        }
        public func capture() throws -> FileOwnershipLease {
            mutex.lock(); defer { mutex.unlock() }
            guard let lease, lease.isHeld else { throw LeaseError.owned }
            return lease
        }
    }

    private var isHeld: Bool {
        mutex.lock(); defer { mutex.unlock() }
        #if os(Windows)
        return handle != nil
        #else
        return descriptor >= 0
        #endif
    }

    public func release() {
        mutex.lock(); defer { mutex.unlock() }
        #if os(Windows)
        if let handle { _ = CloseHandle(handle); self.handle = nil }
        #elseif canImport(Darwin) || canImport(Glibc)
        if descriptor >= 0 { _ = close(descriptor); descriptor = -1 }
        #endif
    }
    deinit { release() }
}
