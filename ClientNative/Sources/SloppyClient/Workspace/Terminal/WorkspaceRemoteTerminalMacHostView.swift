#if os(macOS)
import AppKit
import Foundation
import SloppyClientCore
import SloppyRemoteProtocol
import SwiftTerm
import SwiftUI

@MainActor
final class WorkspaceRemoteTerminalMacHostController: NSObject, WorkspaceTerminalHosting, @preconcurrency TerminalViewDelegate {
    weak var terminalView: TerminalView?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var configuration: WorkspaceTerminalSession.RemoteConfiguration?
    private var managedStreamID: UUID?
    private var isReady = false

    func connect(
        terminalView: TerminalView,
        configuration: WorkspaceTerminalSession.RemoteConfiguration
    ) {
        self.terminalView = terminalView
        self.configuration = configuration
        terminalView.terminalDelegate = self

        receiveTask = Task { [weak self] in
            guard let self else { return }
            if let deviceID = configuration.managedDeviceID {
                do {
                    let stream = try await ManagedRemoteConnection.shared.openStream(
                        to: deviceID,
                        kind: "terminal.stream",
                        path: "/v1/dashboard/terminal/ws"
                    )
                    self.managedStreamID = stream.id
                    await self.receiveManaged(stream.frames)
                } catch {
                    self.terminalView?.feed(byteArray: Array("\r\nManaged terminal unavailable.\r\n".utf8)[...])
                }
                return
            }
            let token = await configuration.apiClient.currentAccessToken()
            guard !Task.isCancelled,
                  let url = Self.webSocketURL(configuration: configuration) else {
                return
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            let socket = ClientURLSessionFactory.session(
                for: configuration.apiClient.baseURL
            ).webSocketTask(with: request)
            self.socket = socket
            socket.resume()
            await self.send(RemoteTerminalClientFrame(type: "auth", token: token))
            await self.receiveLoop(socket: socket)
        }
    }

    func disconnect() {
        if isReady {
            Task { await send(RemoteTerminalClientFrame(type: "close")) }
        }
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        managedStreamID = nil
        terminalView = nil
        configuration = nil
        isReady = false
    }

    func focus() {
        guard let terminalView else { return }
        terminalView.window?.makeFirstResponder(terminalView)
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        guard isReady else { return }
        let text = String(decoding: data, as: UTF8.self)
        Task { await send(RemoteTerminalClientFrame(type: "input", data: text)) }
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        guard isReady else { return }
        Task {
            await send(
                RemoteTerminalClientFrame(
                    type: "resize",
                    cols: newCols,
                    rows: newRows
                )
            )
        }
    }

    func setTerminalTitle(source: TerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func scrolled(source: TerminalView, position: Double) {}

    func clipboardCopy(source: TerminalView, content: Data) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(decoding: content, as: UTF8.self), forType: .string)
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    private func receiveLoop(socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case .string(let text):
                    data = Data(text.utf8)
                case .data(let value):
                    data = value
                @unknown default:
                    continue
                }
                guard let frame = try? JSONDecoder().decode(RemoteTerminalServerFrame.self, from: data) else {
                    continue
                }
                switch frame.type.lowercased() {
                case "authenticated":
                    guard let configuration else { return }
                    await send(
                        RemoteTerminalClientFrame(
                            type: "start",
                            projectId: configuration.projectID,
                            cols: 120,
                            rows: 32
                        )
                    )
                case "ready":
                    isReady = true
                case "output":
                    guard let output = frame.data else { continue }
                    terminalView?.feed(byteArray: Array(output.utf8)[...])
                case "closed", "exit":
                    isReady = false
                    return
                case "error":
                    let message = frame.message ?? frame.code ?? "Remote terminal error"
                    terminalView?.feed(byteArray: Array("\r\n\(message)\r\n".utf8)[...])
                default:
                    break
                }
            } catch {
                if !Task.isCancelled {
                    terminalView?.feed(byteArray: Array("\r\nRemote terminal disconnected.\r\n".utf8)[...])
                }
                return
            }
        }
    }

    private func receiveManaged(_ frames: AsyncStream<RemoteStreamFrame>) async {
        for await frame in frames {
            guard !Task.isCancelled else { return }
            if frame.action == .data, let data = frame.data,
               let terminalFrame = try? JSONDecoder().decode(RemoteTerminalServerFrame.self, from: data) {
                await handleServerFrame(terminalFrame)
            } else if frame.action == .close {
                isReady = false
                return
            }
        }
        isReady = false
    }

    private func handleServerFrame(_ frame: RemoteTerminalServerFrame) async {
        switch frame.type.lowercased() {
        case "authenticated":
            guard let configuration else { return }
            await send(RemoteTerminalClientFrame(
                type: "start", projectId: configuration.projectID, cols: 120, rows: 32
            ))
        case "ready":
            isReady = true
        case "output":
            if let output = frame.data {
                terminalView?.feed(byteArray: Array(output.utf8)[...])
            }
        case "closed", "exit":
            isReady = false
        case "error":
            let message = frame.message ?? frame.code ?? "Remote terminal error"
            terminalView?.feed(byteArray: Array("\r\n\(message)\r\n".utf8)[...])
        default:
            break
        }
    }

    private func send(_ frame: RemoteTerminalClientFrame) async {
        if let managedStreamID, let deviceID = configuration?.managedDeviceID,
           let data = try? JSONEncoder().encode(frame) {
            try? await ManagedRemoteConnection.shared.sendStreamData(
                id: managedStreamID,
                hostID: deviceID,
                kind: "terminal.stream",
                data: data
            )
            return
        }
        guard let socket,
              let data = try? JSONEncoder().encode(frame),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        try? await socket.send(.string(text))
    }

    private static func webSocketURL(
        configuration: WorkspaceTerminalSession.RemoteConfiguration
    ) -> URL? {
        guard var components = URLComponents(
            url: configuration.coordinatorBaseURL,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        let encodedNodeID = BackendHTTPClient.encodePathSegment(configuration.targetNodeID)
        components.path = "/v1/node/mesh/nodes/\(encodedNodeID)/terminal/ws"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

struct WorkspaceRemoteTerminalMacHostView: NSViewRepresentable {
    let session: WorkspaceTerminalSession
    let onHostReady: @MainActor (WorkspaceTerminalHosting) -> Void

    func makeCoordinator() -> WorkspaceRemoteTerminalMacHostController {
        _ = session.remoteTerminalView()
        return session.remoteController ?? WorkspaceRemoteTerminalMacHostController()
    }

    func makeNSView(context: Context) -> TerminalView {
        let terminalView = session.remoteTerminalView()
        onHostReady(context.coordinator)
        return terminalView
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        context.coordinator.terminalView = nsView
    }

    static func dismantleNSView(
        _ nsView: TerminalView,
        coordinator: WorkspaceRemoteTerminalMacHostController
    ) {
        // Keep the socket and terminal buffer alive while the panel is hidden.
    }
}

private struct RemoteTerminalClientFrame: Codable {
    var type: String
    var token: String?
    var projectId: String?
    var cwd: String?
    var cols: Int?
    var rows: Int?
    var data: String?

    init(
        type: String,
        token: String? = nil,
        projectId: String? = nil,
        cwd: String? = nil,
        cols: Int? = nil,
        rows: Int? = nil,
        data: String? = nil
    ) {
        self.type = type
        self.token = token
        self.projectId = projectId
        self.cwd = cwd
        self.cols = cols
        self.rows = rows
        self.data = data
    }
}

private struct RemoteTerminalServerFrame: Decodable {
    var type: String
    var data: String?
    var code: String?
    var message: String?
}
#endif
