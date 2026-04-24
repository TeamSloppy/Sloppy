import Foundation

struct DashboardTerminalClientMessage: Decodable {
    let type: String
    let projectId: String?
    let cwd: String?
    let cols: Int?
    let rows: Int?
    let data: String?
}

struct DashboardTerminalServerMessage: Encodable {
    let type: String
    let sessionId: String?
    let cwd: String?
    let shell: String?
    let pid: Int32?
    let data: String?
    let exitCode: Int32?
    let code: String?
    let message: String?

    init(
        type: String,
        sessionId: String? = nil,
        cwd: String? = nil,
        shell: String? = nil,
        pid: Int32? = nil,
        data: String? = nil,
        exitCode: Int32? = nil,
        code: String? = nil,
        message: String? = nil
    ) {
        self.type = type
        self.sessionId = sessionId
        self.cwd = cwd
        self.shell = shell
        self.pid = pid
        self.data = data
        self.exitCode = exitCode
        self.code = code
        self.message = message
    }
}

struct DashboardTerminalSessionDescriptor: Sendable {
    let sessionID: String
    let cwd: String
    let shell: String
    let pid: Int32
    let events: AsyncStream<DashboardTerminalEvent>
}

extension CoreService {
    enum DashboardTerminalError: Error {
        case disabled
        case remoteAccessDenied
        case invalidProjectID
        case projectNotFound
        case invalidCwd
        case invalidPayload
        case sessionNotFound
        case launchFailed
    }

    func canOpenDashboardTerminal(remoteAddress: String?) -> Bool {
        let terminal = currentConfig.ui.dashboardTerminal
        guard terminal.enabled else {
            return false
        }
        if terminal.localOnly {
            return isLoopbackAddress(remoteAddress)
        }
        return true
    }

    func startDashboardTerminalSession(
        projectID: String?,
        cwd: String?,
        cols: Int,
        rows: Int,
        remoteAddress: String?
    ) async throws -> DashboardTerminalSessionDescriptor {
        guard currentConfig.ui.dashboardTerminal.enabled else {
            throw DashboardTerminalError.disabled
        }
        if currentConfig.ui.dashboardTerminal.localOnly, !isLoopbackAddress(remoteAddress) {
            throw DashboardTerminalError.remoteAccessDenied
        }

        let cwdURL = try await resolvedDashboardTerminalCwd(projectID: projectID, cwd: cwd)
        do {
            let started = try await dashboardTerminalService.startSession(cwd: cwdURL, cols: cols, rows: rows)
            return DashboardTerminalSessionDescriptor(
                sessionID: started.sessionID,
                cwd: started.cwd,
                shell: started.shell,
                pid: started.pid,
                events: started.events
            )
        } catch DashboardTerminalService.ServiceError.invalidSize {
            throw DashboardTerminalError.invalidPayload
        } catch DashboardTerminalService.ServiceError.launchFailed {
            throw DashboardTerminalError.launchFailed
        } catch {
            throw DashboardTerminalError.launchFailed
        }
    }

    func writeDashboardTerminalInput(sessionID: String, data: String) async throws {
        do {
            try await dashboardTerminalService.sendInput(sessionID: sessionID, data: data)
        } catch DashboardTerminalService.ServiceError.sessionNotFound {
            throw DashboardTerminalError.sessionNotFound
        } catch {
            throw DashboardTerminalError.invalidPayload
        }
    }

    func resizeDashboardTerminalSession(sessionID: String, cols: Int, rows: Int) async throws {
        do {
            try await dashboardTerminalService.resizeSession(sessionID: sessionID, cols: cols, rows: rows)
        } catch DashboardTerminalService.ServiceError.sessionNotFound {
            throw DashboardTerminalError.sessionNotFound
        } catch DashboardTerminalService.ServiceError.invalidSize {
            throw DashboardTerminalError.invalidPayload
        } catch {
            throw DashboardTerminalError.invalidPayload
        }
    }

    func closeDashboardTerminalSession(sessionID: String) async {
        await dashboardTerminalService.closeSession(sessionID: sessionID)
    }

    private func resolvedDashboardTerminalCwd(projectID: String?, cwd: String?) async throws -> URL {
        let rootURL = try await resolvedDashboardTerminalRoot(projectID: projectID)
        let trimmed = cwd?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return rootURL
        }
        guard let resolved = resolveToolPath(trimmed, workspaceRootURL: rootURL, currentDirectoryURL: rootURL, extraRoots: []) else {
            throw DashboardTerminalError.invalidCwd
        }
        return resolved
    }

    private func resolvedDashboardTerminalRoot(projectID: String?) async throws -> URL {
        let trimmedProjectID = projectID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedProjectID.isEmpty else {
            return workspaceRootURL.standardizedFileURL
        }

        do {
            return try await resolveProjectWorkspaceRoot(projectID: trimmedProjectID)
        } catch ProjectError.invalidProjectID {
            throw DashboardTerminalError.invalidProjectID
        } catch ProjectError.notFound {
            throw DashboardTerminalError.projectNotFound
        } catch {
            throw DashboardTerminalError.projectNotFound
        }
    }
}

private func isLoopbackAddress(_ rawAddress: String?) -> Bool {
    let trimmed = rawAddress?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    guard !trimmed.isEmpty else {
        return false
    }

    let normalized = trimmed
        .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        .replacingOccurrences(of: "::ffff:", with: "")

    return normalized == "127.0.0.1" || normalized == "::1" || normalized == "localhost"
}
