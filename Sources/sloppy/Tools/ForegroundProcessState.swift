import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum ForegroundProcessState: Sendable, Equatable {
    case running
    case stopped
}

/// Observes without waitpid: Foundation owns child reaping and exit status.
func foregroundProcessState(_ pid: Int32) -> ForegroundProcessState? {
    #if canImport(Darwin)
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
    return info.pbi_status == UInt32(SSTOP) ? .stopped : .running
    #elseif canImport(Glibc)
    guard let stat = try? String(contentsOfFile: "/proc/\(pid)/stat", encoding: .utf8),
          let end = stat.lastIndex(of: ")"),
          let state = stat[stat.index(after: end)...].split(separator: " ").first else { return nil }
    return state == "T" || state == "t" ? .stopped : .running
    #else
    return nil
    #endif
}
