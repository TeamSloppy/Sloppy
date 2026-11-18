import Foundation
import Testing
@testable import sloppy

#if !os(Windows)
@Test("Closing captured output allows an in-flight read callback to finish")
func processPipeCloseDoesNotBlockInFlightReadCallbacks() throws {
    let pipe = Pipe()
    defer { try? pipe.fileHandleForWriting.close() }
    let buffer = ProcessOutputBuffer(maxBytes: 4096)
    let reader = ProcessPipeReader(handle: pipe.fileHandleForReading, buffer: buffer)
    let payload = Data("final output".utf8)
    try pipe.fileHandleForWriting.write(contentsOf: payload)

    let callback = DispatchGroup()
    callback.enter()
    var callbackFinishedDuringClose = false
    reader.stop(closeHandle: {
        // Linux FileHandle.close synchronizes with its dispatch queue. Model
        // an already scheduled callback that must finish before close returns.
        Thread.detachNewThread {
            reader.drain()
            callback.leave()
        }
        callbackFinishedDuringClose = callback.wait(timeout: .now() + 3) == .success
        try pipe.fileHandleForReading.close()
    })
    #expect(callback.wait(timeout: .now() + 3) == .success)
    #expect(callbackFinishedDuringClose)
    #expect(buffer.snapshot().data == payload)
}
#endif
