import Foundation
import Protocols
import Testing

@Suite("OS journal ownership")
struct HostOwnershipTests {
    @Test
    func exclusiveLeaseReleasesWithoutUnlinkingItsFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lease-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("owner.lock")
        let first = try FileOwnershipLease.acquire(at: path)
        #expect(throws: FileOwnershipLease.LeaseError.owned) { try FileOwnershipLease.acquire(at: path) }
        first.release()
        let second = try FileOwnershipLease.acquire(at: path)
        #expect(FileManager.default.fileExists(atPath: path.path))
        first.release()
        #expect(throws: FileOwnershipLease.LeaseError.owned) { try FileOwnershipLease.acquire(at: path) }
        second.release()
    }

    @Test
    func capturedWriterKeepsAuthorityUntilItsLastCommitAndCannotAttachToASuccessor() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("writer-reference-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("owner.lock")
        let reference = FileOwnershipLease.Reference()
        var owner: FileOwnershipLease? = try FileOwnershipLease.acquire(at: path)
        if let owner { reference.bind(owner) }
        var writer: FileOwnershipLease? = try reference.capture()
        owner = nil
        #expect(throws: FileOwnershipLease.LeaseError.owned) { try FileOwnershipLease.acquire(at: path) }
        withExtendedLifetime(writer) {}
        writer = nil
        #expect(throws: FileOwnershipLease.LeaseError.owned) { try reference.capture() }
        let successor = try FileOwnershipLease.acquire(at: path)
        defer { successor.release() }
        #expect(throws: FileOwnershipLease.LeaseError.owned) { try reference.capture() }
    }

    #if os(Linux) || os(macOS)
    @Test
    func separateProcessCannotAcquireTheParentsLease() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("process-lease-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("owner.lock")
        let lease = try FileOwnershipLease.acquire(at: path)
        defer { lease.release() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["--filter", "HostOwnershipTests.leaseContenderProcess", "--testing-library", "swift-testing"]
        var environment = ProcessInfo.processInfo.environment
        environment["SLOPPY_TEST_CONTENDED_LEASE"] = path.path
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output; process.standardError = output
        try process.run()
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "\(String(decoding: bytes, as: UTF8.self))")
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SLOPPY_TEST_CONTENDED_LEASE"] != nil))
    func leaseContenderProcess() throws {
        let path = try #require(ProcessInfo.processInfo.environment["SLOPPY_TEST_CONTENDED_LEASE"])
        #expect(throws: FileOwnershipLease.LeaseError.owned) { try FileOwnershipLease.acquire(at: URL(fileURLWithPath: path)) }
    }
    #endif
}
