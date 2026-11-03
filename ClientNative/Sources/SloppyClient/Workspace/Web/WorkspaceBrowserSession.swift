import Foundation
import SloppyClientCore

/// One connection and page per task, using the task's own Core endpoint and credentials.
@MainActor
final class WorkspaceBrowserSession {
    var viewModel: WorkspaceWebViewModel {
        didSet {
            guard boundPage != nil, oldValue !== viewModel else { return }
            boundPage?.endAutomation()
            boundPage = viewModel
            viewModel.beginAutomation()
        }
    }
    var agentPaletteID: String?
    weak var workspace: BrowserWorkspaceState?
    private var boundPage: WorkspaceWebViewModel?
    let binding: WorkspaceBrowserBinding
    private let apiClient: SloppyAPIClient
    private var task: Task<Void, Never>?
    private let present: @MainActor () -> Void
    private let devices: WorkspaceDeviceToolRuntime?

    init(apiClient: SloppyAPIClient, agentID: String, sessionID: String,
         viewModel: WorkspaceWebViewModel? = nil, workspace: BrowserWorkspaceState? = nil, agentPaletteID: String? = nil,
         devices: WorkspaceDeviceToolRuntime? = nil, present: @escaping @MainActor () -> Void) {
        self.apiClient = apiClient
        self.viewModel = viewModel ?? WorkspaceWebViewModel()
        self.agentPaletteID = agentPaletteID
        self.workspace = workspace
        self.devices = devices
        var capabilities = workspace == nil ? [] : ["tabs_v1", "groups_v1", "organizer_v1"]
        if devices != nil { capabilities.append("devices_v1") }
        binding = .init(bridgeId: UUID().uuidString, agentId: agentID, sessionId: sessionID,
                        capabilities: capabilities.isEmpty ? nil : capabilities)
        self.present = present
    }

    func start() {
#if os(macOS) || os(iOS)
        guard task == nil else { return }
        boundPage = viewModel
        viewModel.beginAutomation()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await apiClient.registerWorkspaceBrowser(binding)
                while !Task.isCancelled {
                    let response = try await apiClient.pollWorkspaceBrowser(binding)
                    for command in response.commands {
                        try Task.checkCancellation()
                        let result = await execute(command)
                        // Delivery failures must never replay a click or form submission.
                        try await apiClient.completeWorkspaceBrowser(result)
                    }
                    try await Task.sleep(for: .seconds(1))
                }
            } catch is CancellationError {
            } catch {
                viewModel.lastError = "Browser connection: \(error.localizedDescription)"
            }
            devices?.stop()
            // Cleanup needs its own uncancelled task after the polling task is stopped.
            await Task { [apiClient, binding] in
                try? await apiClient.disconnectWorkspaceBrowser(binding)
            }.value
            task = nil
            boundPage?.endAutomation()
            boundPage = nil
        }
#endif
    }

    func stop() {
        task?.cancel()
        devices?.stop()
        viewModel.browserRuntime?.stop()
    }

    func stopAndWait() async {
        stop()
        await task?.value
    }

    func execute(_ command: WorkspaceBrowserCommand) async -> WorkspaceBrowserCompletion {
#if os(macOS) || os(iOS)
        if command.name == "devices" {
            guard let devices else {
                return .init(binding: binding, commandId: command.id, error: "This chat has no macOS Devices connection. Open it in Work on the macOS client.")
            }
            return await devices.execute(command, binding: binding)
        }
        if command.name == "create_note" || command.name == "create_todo" {
            do { return .init(binding: binding, commandId: command.id, data: try executeOrganizer(command.name, input: command.input)) }
            catch { return .init(binding: binding, commandId: command.id, error: error.localizedDescription) }
        }
        if command.name == "tabs" || command.name == "groups" {
            do { return .init(binding: binding, commandId: command.id, data: try command.name == "tabs" ? executeTabs(command.input) : executeGroups(command.input)) }
            catch { return .init(binding: binding, commandId: command.id, error: error.localizedDescription) }
        }
        let pageModel = viewModel
        pageModel.beginAutomation()
        defer { pageModel.endAutomation() }
        do {
            let runtime = pageModel.ensureBrowserRuntime()
            runtime.agentID = binding.agentId
            runtime.agentPaletteID = agentPaletteID
            defer { runtime.agentID = nil; runtime.agentPointer.clear() }
            if let pageID = command.input.pageId, pageID != runtime.pageID {
                throw WorkspaceBrowserRuntimeError.invalidArguments
            }
            present()
            // Allow SwiftUI to attach the retained page before taking a snapshot.
            try await Task.sleep(for: .milliseconds(100))
            if let workspace, !workspace.pages.values.contains(where: { $0 === pageModel }) {
                throw WorkspaceBrowserRuntimeError.evaluationFailed("The target tab was closed. List tabs before retrying.")
            }
            var imageBase64: String?
            var page: WorkspaceBrowserPage
            switch command.name {
            case "open", "navigate":
                page = try await runtime.open(url: command.input.url ?? "about:blank")
            case "read":
                page = try await runtime.read()
            case "evaluate":
                guard let expression = command.input.expression else { throw WorkspaceBrowserRuntimeError.invalidArguments }
                let value = try await runtime.evaluate(expression: expression)
                page = try await runtime.read()
                page.evaluation = .init(value: value)
            case "click":
                guard let selector = command.input.selector else { throw WorkspaceBrowserRuntimeError.invalidArguments }
                _ = try await runtime.click(selector: selector)
                page = try await runtime.read()
            case "type":
                guard let selector = command.input.selector, let text = command.input.text else { throw WorkspaceBrowserRuntimeError.invalidArguments }
                _ = try await runtime.type(selector: selector, text: text)
                page = try await runtime.read()
            case "scroll":
                if let selector = command.input.selector {
                    _ = try await runtime.scrollTo(selector: selector)
                } else {
                    _ = try await runtime.scroll(x: command.input.x ?? 0, y: command.input.y ?? 0)
                }
                page = try await runtime.read()
            case "screenshot":
                imageBase64 = try await runtime.screenshot().imageData.base64EncodedString()
                page = try await runtime.read()
            case "close":
                page = try await runtime.open(url: "about:blank")
                page.running = false
            default:
                throw WorkspaceBrowserRuntimeError.invalidArguments
            }
            return .init(binding: binding, commandId: command.id, data: page, imageBase64: imageBase64)
        } catch {
            return .init(binding: binding, commandId: command.id, error: error.localizedDescription)
        }
#else
        return .init(binding: binding, commandId: command.id, error: "Browser automation requires macOS or iOS.")
#endif
    }
}
