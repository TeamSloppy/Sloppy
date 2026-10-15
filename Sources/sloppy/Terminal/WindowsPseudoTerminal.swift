#if os(Windows)
import Foundation
import WinSDK

/// A ConPTY session. The reader owns duplicate handles so closing a session can safely unblock it.
final class WindowsPseudoTerminal: @unchecked Sendable {
    private let lock = NSLock()
    private var console: HPCON?
    private var input: HANDLE?
    private var output: HANDLE?
    private var process: HANDLE?
    let pid: Int32

    init(shell: String, arguments: [String] = [], cwd: String, cols: Int, rows: Int) throws {
        var inputRead: HANDLE?, inputWrite: HANDLE?, outputRead: HANDLE?, outputWrite: HANDLE?
        guard CreatePipe(&inputRead, &inputWrite, nil, 0) else { throw DashboardTerminalService.ServiceError.launchFailed }
        defer { if let inputRead { CloseHandle(inputRead) } }
        guard CreatePipe(&outputRead, &outputWrite, nil, 0) else {
            if let inputWrite { CloseHandle(inputWrite) }
            throw DashboardTerminalService.ServiceError.launchFailed
        }
        defer { if let outputWrite { CloseHandle(outputWrite) } }
        var console: HPCON?
        let size = COORD(X: SHORT(clamping: cols), Y: SHORT(clamping: rows))
        guard CreatePseudoConsole(size, inputRead, outputWrite, 0, &console) == S_OK, let console else {
            if let inputWrite { CloseHandle(inputWrite) }
            if let outputRead { CloseHandle(outputRead) }
            throw DashboardTerminalService.ServiceError.launchFailed
        }
        var succeeded = false
        defer {
            if !succeeded {
                ClosePseudoConsole(console)
                if let inputWrite { CloseHandle(inputWrite) }
                if let outputRead { CloseHandle(outputRead) }
            }
        }
        var bytes: SIZE_T = 0
        _ = InitializeProcThreadAttributeList(nil, 1, 0, &bytes)
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(bytes), alignment: MemoryLayout<UInt>.alignment)
        defer { storage.deallocate() }
        let attributes = OpaquePointer(storage)
        guard InitializeProcThreadAttributeList(attributes, 1, 0, &bytes) else {
            throw DashboardTerminalService.ServiceError.launchFailed
        }
        defer { DeleteProcThreadAttributeList(attributes) }
        guard UpdateProcThreadAttribute(attributes, 0, DWORD_PTR(PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE),
                                        console, SIZE_T(MemoryLayout<HPCON>.size), nil, nil) else {
            throw DashboardTerminalService.ServiceError.launchFailed
        }
        var startup = STARTUPINFOEXW()
        startup.StartupInfo.cb = DWORD(MemoryLayout<STARTUPINFOEXW>.size)
        // Null standard handles force attachment to ConPTY even when Core's stdio is redirected.
        startup.StartupInfo.dwFlags = DWORD(STARTF_USESTDHANDLES)
        startup.lpAttributeList = attributes
        var information = PROCESS_INFORMATION()
        var command = Array(([shell] + arguments).map(Self.quotedArgument).joined(separator: " ").utf16) + [0]
        let launched = cwd.withCString(encodedAs: UTF16.self) { directory in
            withUnsafeMutablePointer(to: &startup) { pointer in
                pointer.withMemoryRebound(to: STARTUPINFOW.self, capacity: 1) {
                    CreateProcessW(nil, &command, nil, nil, false, DWORD(EXTENDED_STARTUPINFO_PRESENT),
                                   nil, directory, $0, &information)
                }
            }
        }
        guard launched else { throw DashboardTerminalService.ServiceError.launchFailed }
        CloseHandle(information.hThread)
        self.console = console
        self.input = inputWrite
        self.output = outputRead
        self.process = information.hProcess
        self.pid = Int32(bitPattern: information.dwProcessId)
        succeeded = true
    }

    func send(_ text: String) throws {
        try lock.withLock {
            guard let input else { throw DashboardTerminalService.ServiceError.writeFailed }
            let data = Data(text.utf8)
            try data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    var written: DWORD = 0
                    guard WriteFile(input, bytes.baseAddress?.advanced(by: offset), DWORD(bytes.count - offset), &written, nil),
                          written > 0 else { throw DashboardTerminalService.ServiceError.writeFailed }
                    offset += Int(written)
                }
            }
        }
    }

    func resize(cols: Int, rows: Int) throws {
        try lock.withLock {
            guard let console, ResizePseudoConsole(console, COORD(X: SHORT(clamping: cols), Y: SHORT(clamping: rows))) == S_OK else {
                throw DashboardTerminalService.ServiceError.resizeFailed
            }
        }
    }

    func read(onOutput: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable (Int32) -> Void) {
        let handles: (HANDLE, HANDLE)? = lock.withLock {
            guard let output, let process else { return nil }
            var reader: HANDLE?, waiter: HANDLE?
            let current = GetCurrentProcess()
            guard DuplicateHandle(current, output, current, &reader, 0, false, DWORD(DUPLICATE_SAME_ACCESS)), let reader else { return nil }
            guard DuplicateHandle(current, process, current, &waiter, 0, false, DWORD(DUPLICATE_SAME_ACCESS)), let waiter else {
                CloseHandle(reader); return nil
            }
            return (reader, waiter)
        }
        guard let handles else { onExit(-1); return }
        // Wrapping the handles in this Sendable owner also keeps them alive until the blocking reads finish.
        let reader = WindowsTerminalReader(output: handles.0, process: handles.1)
        DispatchQueue.global(qos: .utility).async { [self] in
            _ = WaitForSingleObject(reader.process, INFINITE)
            // Closing ConPTY ends its output stream; the reader must remain active while it closes.
            close()
        }
        DispatchQueue.global(qos: .utility).async {
            reader.run(onOutput: onOutput, onExit: onExit)
        }
    }

    func close() {
        lock.withLock {
            if let process { _ = TerminateProcess(process, 1) }
            if let input { CloseHandle(input); self.input = nil }
            if let console { ClosePseudoConsole(console); self.console = nil }
            if let output { CloseHandle(output); self.output = nil }
            if let process { CloseHandle(process); self.process = nil }
        }
    }

    deinit { close() }

    private static func quotedArgument(_ value: String) -> String {
        var result = "\""
        var backslashes = 0
        for character in value {
            if character == "\\" { backslashes += 1; continue }
            if character == "\"" {
                result += String(repeating: "\\", count: backslashes * 2 + 1) + "\""
            } else {
                result += String(repeating: "\\", count: backslashes) + String(character)
            }
            backslashes = 0
        }
        return result + String(repeating: "\\", count: backslashes * 2) + "\""
    }
}

private final class WindowsTerminalReader: @unchecked Sendable {
    let output: HANDLE
    let process: HANDLE
    init(output: HANDLE, process: HANDLE) { self.output = output; self.process = process }

    func run(onOutput: (String) -> Void, onExit: (Int32) -> Void) {
        defer { CloseHandle(output) }
        var buffer = [UInt8](repeating: 0, count: 4096)
        var pending = Data()
        while true {
            var count: DWORD = 0
            guard ReadFile(output, &buffer, DWORD(buffer.count), &count, nil), count > 0 else { break }
            pending.append(contentsOf: buffer.prefix(Int(count)))
            // Preserve a UTF-8 character split across two pipe reads.
            var end = pending.count
            if let start = pending.lastIndex(where: { $0 & 0xC0 != 0x80 }) {
                let first = pending[start]
                let length = first < 0x80 ? 1 : first < 0xE0 ? 2 : first < 0xF0 ? 3 : 4
                if pending.count - start < length { end = start }
            }
            if end > 0 { onOutput(String(decoding: pending.prefix(end), as: UTF8.self)); pending = Data(pending.dropFirst(end)) }
        }
        if !pending.isEmpty { onOutput(String(decoding: pending, as: UTF8.self)) }
        _ = WaitForSingleObject(process, INFINITE)
        var code: DWORD = 1
        _ = GetExitCodeProcess(process, &code)
        onExit(Int32(bitPattern: code))
    }

    deinit { CloseHandle(process) }
}
#endif
