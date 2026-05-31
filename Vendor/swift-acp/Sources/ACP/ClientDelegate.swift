//
//  ClientDelegate.swift
//  ACP
//
//  Main delegate protocol for ACP client
//

import Foundation
import ACPModel

/// Protocol for handling incoming ACP requests from the agent
public protocol ClientDelegate: AnyObject, Sendable {
    /// Handle file read request
    func handleFileReadRequest(_ path: String, sessionId: String, line: Int?, limit: Int?) async throws -> ReadTextFileResponse

    /// Handle file write request
    func handleFileWriteRequest(_ path: String, content: String, sessionId: String) async throws -> WriteTextFileResponse

    /// Handle terminal create request
    func handleTerminalCreate(command: String, sessionId: String, args: [String]?, cwd: String?, env: [EnvVariable]?, outputByteLimit: Int?) async throws -> CreateTerminalResponse

    /// Handle terminal output request
    func handleTerminalOutput(terminalId: TerminalId, sessionId: String) async throws -> TerminalOutputResponse

    /// Handle terminal wait for exit request
    func handleTerminalWaitForExit(terminalId: TerminalId, sessionId: String) async throws -> WaitForExitResponse

    /// Handle terminal kill request
    func handleTerminalKill(terminalId: TerminalId, sessionId: String) async throws -> KillTerminalResponse

    /// Handle terminal release request
    func handleTerminalRelease(terminalId: TerminalId, sessionId: String) async throws -> ReleaseTerminalResponse

    /// Handle permission request
    func handlePermissionRequest(request: RequestPermissionRequest) async throws -> RequestPermissionResponse
}

// MARK: - Typealiases for backward compatibility

@available(*, deprecated, renamed: "ClientDelegate")
public typealias ACPClientDelegate = ClientDelegate
