import Foundation
import SloppyClientCore

/// One connection and page per task, using the task's own Core endpoint and credentials.
@MainActor
final class WorkspaceBrowserSession {
    let viewModel = WorkspaceWebViewModel()
    let binding: WorkspaceBrowserBinding
    private let apiClient: SloppyAPIClient
    private var task: Task<Void, Never>?
    private let present: @MainActor () -> Void

    init(apiClient: SloppyAPIClient, agentID: String, sessionID: String,
         present: @escaping @MainActor () -> Void) {
        self.apiClient = apiClient
        binding = .init(bridgeId: UUID().uuidString, agentId: agentID, sessionId: sessionID)
        self.present = present
    }

    func start() {
#if os(macOS)
        guard task == nil else { return }
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
            // Cleanup needs its own uncancelled task after the polling task is stopped.
            await Task { [apiClient, binding] in
                try? await apiClient.disconnectWorkspaceBrowser(binding)
            }.value
            task = nil
        }
#endif
    }

    func stop() {
        task?.cancel()
        viewModel.browserRuntime?.stop()
    }

    private func execute(_ command: WorkspaceBrowserCommand) async -> WorkspaceBrowserCompletion {
#if os(macOS)
        do {
            let runtime = viewModel.ensureBrowserRuntime()
            if let pageID = command.input.pageId, pageID != runtime.pageID {
                throw WorkspaceBrowserRuntimeError.invalidArguments
            }
            present()
            // Allow SwiftUI to attach the retained page before taking a snapshot.
            try await Task.sleep(for: .milliseconds(100))
            var imageBase64: String?
            var page: WorkspaceBrowserPage
            switch command.name {
            case "open", "navigate":
                page = try await runtime.open(url: command.input.url ?? "about:blank")
            case "read":
                page = try await runtime.read()
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
        return .init(binding: binding, commandId: command.id, error: "Browser automation requires macOS.")
#endif
    }
}
