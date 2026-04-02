import Foundation
import LanguageServerProtocol
import LanguageServerProtocolTransport
import Logging
import Protocols

// MARK: - LSPServerError

enum LSPServerError: Error, LocalizedError {
    case serverNotFound(String)
    case serverDisabled(String)
    case invalidCommand(String)
    case initializationFailed(String)
    case noItemsForCallHierarchy
    case fileTooLarge(String)

    var errorDescription: String? {
        switch self {
        case .serverNotFound(let ext):
            return "No LSP server configured for extension '\(ext)'."
        case .serverDisabled(let id):
            return "LSP server '\(id)' is disabled."
        case .invalidCommand(let id):
            return "LSP server '\(id)' has an empty or missing command."
        case .initializationFailed(let message):
            return "LSP server initialization failed: \(message)"
        case .noItemsForCallHierarchy:
            return "No call hierarchy items found at the given position."
        case .fileTooLarge(let path):
            return "File '\(path)' exceeds the maximum size for LSP sync."
        }
    }
}

// MARK: - LSPServerInstance

/// Manages lifecycle and requests for a single LSP server process.
actor LSPServerInstance {
    private let config: CoreConfig.LSP.Server
    private let workspaceRootURL: URL
    private let logger: Logger

    private var connection: JSONRPCConnection?
    private var process: Process?
    private var openedFiles: Set<String> = []
    private var isInitialized = false

    private static let maxFileSizeBytes = 10 * 1024 * 1024 // 10 MB

    init(config: CoreConfig.LSP.Server, workspaceRootURL: URL, logger: Logger) {
        self.config = config
        self.workspaceRootURL = workspaceRootURL
        self.logger = logger
    }

    func shutdown() {
        connection?.close()
        connection = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        openedFiles = []
        isInitialized = false
    }

    // MARK: - LSP Operations

    func definition(uri: DocumentURI, position: Position) async throws -> LocationsOrLocationLinksResponse? {
        let conn = try await ensureInitialized()
        let request = DefinitionRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: position
        )
        return try await send(request, on: conn)
    }

    func references(uri: DocumentURI, position: Position) async throws -> [Location] {
        let conn = try await ensureInitialized()
        let request = ReferencesRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: position,
            context: ReferencesContext(includeDeclaration: true)
        )
        return try await send(request, on: conn) ?? []
    }

    func hover(uri: DocumentURI, position: Position) async throws -> HoverResponse? {
        let conn = try await ensureInitialized()
        let request = HoverRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: position
        )
        return try await send(request, on: conn) ?? nil
    }

    func documentSymbol(uri: DocumentURI) async throws -> DocumentSymbolResponse? {
        let conn = try await ensureInitialized()
        let request = DocumentSymbolRequest(textDocument: TextDocumentIdentifier(uri))
        return try await send(request, on: conn) ?? nil
    }

    func workspaceSymbol(query: String) async throws -> [WorkspaceSymbolItem] {
        let conn = try await ensureInitialized()
        let request = WorkspaceSymbolsRequest(query: query)
        return try await send(request, on: conn) ?? []
    }

    func implementation(uri: DocumentURI, position: Position) async throws -> LocationsOrLocationLinksResponse? {
        let conn = try await ensureInitialized()
        let request = ImplementationRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: position
        )
        return try await send(request, on: conn) ?? nil
    }

    func prepareCallHierarchy(uri: DocumentURI, position: Position) async throws -> [CallHierarchyItem] {
        let conn = try await ensureInitialized()
        let request = CallHierarchyPrepareRequest(
            textDocument: TextDocumentIdentifier(uri),
            position: position
        )
        return try await send(request, on: conn) ?? []
    }

    func incomingCalls(uri: DocumentURI, position: Position) async throws -> [CallHierarchyIncomingCall] {
        let items = try await prepareCallHierarchy(uri: uri, position: position)
        guard let item = items.first else {
            throw LSPServerError.noItemsForCallHierarchy
        }
        let conn = try await ensureInitialized()
        let request = CallHierarchyIncomingCallsRequest(item: item)
        return try await send(request, on: conn) ?? []
    }

    func outgoingCalls(uri: DocumentURI, position: Position) async throws -> [CallHierarchyOutgoingCall] {
        let items = try await prepareCallHierarchy(uri: uri, position: position)
        guard let item = items.first else {
            throw LSPServerError.noItemsForCallHierarchy
        }
        let conn = try await ensureInitialized()
        let request = CallHierarchyOutgoingCallsRequest(item: item)
        return try await send(request, on: conn) ?? []
    }

    // MARK: - File Sync

    func openFileIfNeeded(uri: DocumentURI, filePath: String) async throws {
        guard !openedFiles.contains(filePath) else { return }
        let conn = try await ensureInitialized()
        let fileURL = URL(fileURLWithPath: filePath)
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard data.count <= Self.maxFileSizeBytes else {
            throw LSPServerError.fileTooLarge(filePath)
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        let ext = (filePath as NSString).pathExtension
        let language = Language(rawValue: ext.isEmpty ? "plaintext" : ext)
        let item = TextDocumentItem(uri: uri, language: language, version: 1, text: text)
        conn.send(DidOpenTextDocumentNotification(textDocument: item))
        openedFiles.insert(filePath)
    }

    // MARK: - Connection lifecycle

    private func ensureInitialized() async throws -> JSONRPCConnection {
        if let connection, isInitialized {
            return connection
        }
        return try await startAndInitialize()
    }

    private func startAndInitialize() async throws -> JSONRPCConnection {
        let command = config.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw LSPServerError.invalidCommand(config.id)
        }

        let executableURL: URL
        let arguments: [String]
        if command.hasPrefix("/") || command.hasPrefix(".") {
            executableURL = URL(fileURLWithPath: command)
            arguments = config.arguments
        } else {
            executableURL = URL(fileURLWithPath: "/usr/bin/env")
            arguments = [command] + config.arguments
        }

        let clientToServer = Pipe()
        let serverToClient = Pipe()

        let messageRegistry = MessageRegistry(
            requests: builtinRequests,
            notifications: builtinNotifications
        )

        let conn = JSONRPCConnection(
            name: "\(config.id)-lsp",
            protocol: messageRegistry,
            receiveFD: serverToClient.fileHandleForReading,
            sendFD: clientToServer.fileHandleForWriting
        )

        let handler = NullMessageHandler()
        conn.start(receiveHandler: handler) {
            withExtendedLifetime((clientToServer, serverToClient)) {}
        }

        let proc = Process()
        proc.executableURL = executableURL
        proc.arguments = arguments
        proc.standardOutput = serverToClient
        proc.standardInput = clientToServer
        proc.standardError = FileHandle.standardError

        if let cwd = config.cwd.map({ URL(fileURLWithPath: $0, isDirectory: true) }) {
            proc.currentDirectoryURL = cwd
        }

        let serverID = config.id
        proc.terminationHandler = { [weak self] process in
            let reason: JSONRPCConnection.TerminationReason = process.terminationReason == .exit
                ? .exited(exitCode: process.terminationStatus)
                : .uncaughtSignal
            conn.close()
            Task { await self?.handleTermination(reason: reason) }
            _ = serverID
        }

        try proc.run()

        self.connection = conn
        self.process = proc

        try await initialize(conn: conn)
        isInitialized = true
        return conn
    }

    private func initialize(conn: JSONRPCConnection) async throws {
        let rootURI = DocumentURI(workspaceRootURL)
        let capabilities = ClientCapabilities(
            workspace: WorkspaceClientCapabilities(),
            textDocument: TextDocumentClientCapabilities(),
            window: nil,
            general: nil,
            experimental: nil
        )
        let request = InitializeRequest(
            processId: Int(ProcessInfo.processInfo.processIdentifier),
            clientInfo: InitializeRequest.ClientInfo(name: "sloppy", version: "1.0.0"),
            rootURI: rootURI,
            capabilities: capabilities,
            workspaceFolders: [WorkspaceFolder(uri: rootURI, name: workspaceRootURL.lastPathComponent)]
        )

        _ = try await send(request, on: conn)
        conn.send(InitializedNotification())
    }

    private func handleTermination(reason: JSONRPCConnection.TerminationReason) {
        logger.warning("LSP server '\(config.id)' terminated: \(String(describing: reason))")
        connection = nil
        process = nil
        isInitialized = false
        openedFiles = []
    }

    // MARK: - Async send helper

    private func send<R: RequestType>(_ request: R, on conn: JSONRPCConnection) async throws -> R.Response {
        try await withCheckedThrowingContinuation { continuation in
            conn.send(request) { result in
                switch result {
                case .success(let response):
                    continuation.resume(returning: response)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - NullMessageHandler

/// Minimal handler for server-initiated requests (notifications, etc.) that we don't need to act on.
private final class NullMessageHandler: MessageHandler {
    func handle(_ notification: some NotificationType) {}

    func handle<R: RequestType>(
        _ request: R,
        id: RequestID,
        reply: @Sendable @escaping (LSPResult<R.Response>) -> Void
    ) {
        reply(.failure(ResponseError.methodNotFound(R.method)))
    }
}

// MARK: - LSPServerManager

/// Routes LSP requests to the appropriate server based on file extension.
actor LSPServerManager {
    private var config: CoreConfig.LSP
    private var workspaceRootURL: URL
    private let logger: Logger
    private var instances: [String: LSPServerInstance] = [:]

    init(
        config: CoreConfig.LSP,
        workspaceRootURL: URL,
        logger: Logger = Logger(label: "sloppy.lsp")
    ) {
        self.config = config
        self.workspaceRootURL = workspaceRootURL
        self.logger = logger
    }

    func updateConfig(_ config: CoreConfig.LSP, workspaceRootURL: URL) async {
        let nextIDs = Set(config.servers.map(\.id))
        let obsolete = instances.keys.filter { !nextIDs.contains($0) }
        for id in obsolete {
            await instances[id]?.shutdown()
            instances.removeValue(forKey: id)
        }
        self.config = config
        self.workspaceRootURL = workspaceRootURL
    }

    func shutdown() async {
        for instance in instances.values {
            await instance.shutdown()
        }
        instances.removeAll()
    }

    func instance(for filePath: String) throws -> LSPServerInstance {
        let ext = "." + (filePath as NSString).pathExtension
        guard let serverConfig = config.servers.first(where: {
            $0.enabled && $0.extensions.contains(ext)
        }) else {
            throw LSPServerError.serverNotFound(ext)
        }
        if let existing = instances[serverConfig.id] {
            return existing
        }
        let instance = LSPServerInstance(
            config: serverConfig,
            workspaceRootURL: workspaceRootURL,
            logger: Logger(label: "sloppy.lsp.\(serverConfig.id)")
        )
        instances[serverConfig.id] = instance
        return instance
    }
}
