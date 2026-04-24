import Darwin
import Foundation

enum DashboardTerminalEvent: Sendable {
    case output(String)
    case exit(Int32)
    case error(code: String, message: String)
    case closed
}

actor DashboardTerminalService {
    enum ServiceError: Error {
        case invalidSize
        case launchFailed
        case sessionNotFound
        case writeFailed
        case resizeFailed
    }

    struct StartedSession: Sendable {
        let sessionID: String
        let cwd: String
        let shell: String
        let pid: Int32
        let events: AsyncStream<DashboardTerminalEvent>
    }

    private struct SessionState {
        let id: String
        let masterFD: Int32
        let pid: Int32
        let cwd: String
        let shell: String
        let continuation: AsyncStream<DashboardTerminalEvent>.Continuation
    }

    private var sessions: [String: SessionState] = [:]

    func startSession(cwd: URL, cols: Int, rows: Int) throws -> StartedSession {
        guard cols > 0, rows > 0 else {
            throw ServiceError.invalidSize
        }

        let shell = preferredShell()
        let cwdPath = cwd.standardizedFileURL.path

        var continuation: AsyncStream<DashboardTerminalEvent>.Continuation?
        let events = AsyncStream<DashboardTerminalEvent> { next in
            continuation = next
        }

        guard let continuation else {
            throw ServiceError.launchFailed
        }

        var masterFD: Int32 = -1
        var size = winsize(
            ws_row: UInt16(max(1, min(rows, Int(UInt16.max)))),
            ws_col: UInt16(max(1, min(cols, Int(UInt16.max)))),
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        let pid = forkpty(&masterFD, nil, nil, &size)
        guard pid >= 0 else {
            continuation.finish()
            throw ServiceError.launchFailed
        }

        if pid == 0 {
            launchDashboardTerminalChild(shell: shell, cwd: cwdPath)
        }

        let sessionID = "term-\(UUID().uuidString.lowercased())"
        sessions[sessionID] = SessionState(
            id: sessionID,
            masterFD: masterFD,
            pid: pid,
            cwd: cwdPath,
            shell: shell,
            continuation: continuation
        )

        Task.detached(priority: .utility) { [self] in
            await self.readLoop(sessionID: sessionID, masterFD: masterFD)
        }

        Task.detached(priority: .utility) { [self] in
            await self.waitLoop(sessionID: sessionID, pid: pid)
        }

        return StartedSession(
            sessionID: sessionID,
            cwd: cwdPath,
            shell: shell,
            pid: pid,
            events: events
        )
    }

    func sendInput(sessionID: String, data: String) throws {
        guard let session = sessions[sessionID] else {
            throw ServiceError.sessionNotFound
        }
        let bytes = Array(data.utf8)
        let written = bytes.withUnsafeBytes { buffer -> ssize_t in
            guard let baseAddress = buffer.baseAddress else {
                return 0
            }
            return Darwin.write(session.masterFD, baseAddress, buffer.count)
        }
        guard written >= 0 else {
            throw ServiceError.writeFailed
        }
    }

    func resizeSession(sessionID: String, cols: Int, rows: Int) throws {
        guard let session = sessions[sessionID] else {
            throw ServiceError.sessionNotFound
        }
        guard cols > 0, rows > 0 else {
            throw ServiceError.invalidSize
        }

        var size = winsize(
            ws_row: UInt16(max(1, min(rows, Int(UInt16.max)))),
            ws_col: UInt16(max(1, min(cols, Int(UInt16.max)))),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        guard ioctl(session.masterFD, TIOCSWINSZ, &size) == 0 else {
            throw ServiceError.resizeFailed
        }
        _ = Darwin.kill(session.pid, SIGWINCH)
    }

    func closeSession(sessionID: String) {
        guard let session = sessions.removeValue(forKey: sessionID) else {
            return
        }
        terminateProcess(pid: session.pid)
        _ = Darwin.close(session.masterFD)
        session.continuation.yield(.closed)
        session.continuation.finish()
    }

    private func readLoop(sessionID: String, masterFD: Int32) async {
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = Darwin.read(masterFD, &buffer, buffer.count)
            if count > 0 {
                let chunk = String(decoding: buffer.prefix(Int(count)), as: UTF8.self)
                emit(.output(chunk), sessionID: sessionID)
                continue
            }

            if count == 0 {
                break
            }

            if errno == EINTR {
                continue
            }

            if errno == EIO || errno == EBADF {
                break
            }

            let message = String(cString: strerror(errno))
            emit(.error(code: "read_failed", message: message), sessionID: sessionID)
            break
        }
    }

    private func waitLoop(sessionID: String, pid: Int32) async {
        var status: Int32 = 0
        while true {
            let result = waitpid(pid, &status, 0)
            if result == -1 && errno == EINTR {
                continue
            }
            break
        }

        let exitCode: Int32
        if processExited(status) {
            exitCode = processExitStatus(status)
        } else if processSignaled(status) {
            exitCode = 128 + processTermSignal(status)
        } else {
            exitCode = -1
        }

        finishExitedSession(sessionID: sessionID, exitCode: exitCode)
    }

    private func emit(_ event: DashboardTerminalEvent, sessionID: String) {
        guard let session = sessions[sessionID] else {
            return
        }
        session.continuation.yield(event)
    }

    private func finishExitedSession(sessionID: String, exitCode: Int32) {
        guard let session = sessions.removeValue(forKey: sessionID) else {
            return
        }
        _ = Darwin.close(session.masterFD)
        session.continuation.yield(.exit(exitCode))
        session.continuation.yield(.closed)
        session.continuation.finish()
    }
}

private func preferredShell() -> String {
    let envShell = ProcessInfo.processInfo.environment["SHELL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !envShell.isEmpty {
        return envShell
    }
    return "/bin/zsh"
}

private func terminateProcess(pid: Int32) {
    guard pid > 0 else {
        return
    }
    _ = Darwin.kill(pid, SIGHUP)
    _ = Darwin.kill(pid, SIGCONT)
}

private func launchDashboardTerminalChild(shell: String, cwd: String) -> Never {
    _ = Darwin.chdir(cwd)
    _ = Darwin.setenv("TERM", "xterm-256color", 1)
    _ = Darwin.setenv("COLORTERM", "truecolor", 1)

    let shellPointer = strdup(shell)
    let loginPointer = strdup("-l")
    var arguments: [UnsafeMutablePointer<CChar>?] = [shellPointer, loginPointer, nil]
    execv(shellPointer, &arguments)

    _exit(127)
}

private func processExited(_ status: Int32) -> Bool {
    (status & 0x7f) == 0
}

private func processExitStatus(_ status: Int32) -> Int32 {
    (status >> 8) & 0xff
}

private func processSignaled(_ status: Int32) -> Bool {
    let signal = status & 0x7f
    return signal != 0 && signal != 0x7f
}

private func processTermSignal(_ status: Int32) -> Int32 {
    status & 0x7f
}
