import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// An exiting child must produce a recoverable write error, not terminate Core.
func makeProcessInputPipe() throws -> Pipe {
    let pipe = Pipe()
#if canImport(Darwin)
    guard fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
#endif
    return pipe
}
