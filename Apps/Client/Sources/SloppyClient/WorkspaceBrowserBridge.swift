import Foundation
import SloppyClientCore

extension WorkspaceBrowserModel {
    func bind(service: WorkspaceService, agentID: String?, sessionID: String?) {
        if binding?.agentId == agentID && binding?.sessionId == sessionID { return }
        bridgeTask?.cancel(); bridgeTask = nil
        binding = nil
        guard let agentID, let sessionID else { bridgeStatus = "Open a chat to connect agent browser tools."; return }
        let binding = WorkspaceBrowserBinding(bridgeId: UUID().uuidString, agentId: agentID, sessionId: sessionID)
        self.binding = binding
        bridgeTask = Task { [weak self] in
            do {
                try await service.registerBrowser(binding)
                self?.bridgeStatus = "Agent browser connected"
                while !Task.isCancelled {
                    let commands = try await service.pollBrowser(binding)
                    for command in commands.commands {
                        try Task.checkCancellation()
                        guard let self else { return }
                        let result = await execute(command, binding: binding)
                        // A failed acknowledgement stops polling; clicks are never replayed.
                        try await service.completeBrowser(result)
                    }
                    try await Task.sleep(for: .seconds(1))
                }
            } catch is CancellationError {} catch { self?.bridgeStatus = error.localizedDescription }
            await Task { try? await service.disconnectBrowser(binding) }.value
        }
    }

    func execute(_ command: WorkspaceBrowserCommand, binding: WorkspaceBrowserBinding) async -> WorkspaceBrowserCompletion {
        do {
            guard command.input.pageId == nil || command.input.pageId == pageID else { throw WorkspaceBrowserError.command("Unknown browser page.") }
            try await runtime.start(executable: executable)
            isRunning = true; startFrames()
            var image: String?
            switch command.name {
            case "open", "navigate":
                if let url = command.input.url, url != "about:blank" { try await runtime.navigate(url); address = url }
            case "read": break
            case "click":
                guard let selector = command.input.selector else { throw WorkspaceBrowserError.command("Missing selector.") }
                _ = try await evaluate("(() => { const el=document.querySelector(\(literal(selector))); if(!el) throw Error('Element not found'); el.click(); return true; })()")
            case "type":
                guard let selector = command.input.selector, let text = command.input.text else { throw WorkspaceBrowserError.command("Missing selector or text.") }
                _ = try await evaluate("(() => { const el=document.querySelector(\(literal(selector))); if(!el) throw Error('Element not found'); el.focus(); el.select?.(); return true; })()")
                _ = try await runtime.command("Input.insertText", params: ["text": .string(text)])
            case "scroll":
                if let selector = command.input.selector {
                    _ = try await evaluate("document.querySelector(\(literal(selector)))?.scrollIntoView({block:'center'})")
                } else {
                    let x = command.input.x ?? 0, y = command.input.y ?? 0
                    guard x.isFinite, y.isFinite else { throw WorkspaceBrowserError.command("Invalid scroll position.") }
                    _ = try await evaluate("scrollBy(\(x),\(y))")
                }
            case "screenshot": image = try await runtime.screenshot().base64EncodedString()
            case "close":
                stop()
                return .init(binding: binding, commandId: command.id, data: .init(pageId: pageID, url: "about:blank", title: "", visibleText: "", running: false))
            default: throw WorkspaceBrowserError.command("Unsupported browser command: \(command.name)")
            }
            let result = try await evaluate(Self.readScript)
            let page = try result.decoded(WorkspaceBrowserSnapshot.self)
            return .init(binding: binding, commandId: command.id,
                data: .init(pageId: pageID, url: page.url, title: page.title, visibleText: page.visibleText, elements: page.elements), imageBase64: image)
        } catch { return .init(binding: binding, commandId: command.id, error: error.localizedDescription) }
    }

    private func evaluate(_ script: String) async throws -> ConfigJSONValue {
        let result = try await runtime.command("Runtime.evaluate", params: ["expression": .string(script), "returnByValue": .bool(true), "awaitPromise": .bool(true)])
        if result["exceptionDetails"] != .null { throw WorkspaceBrowserError.command("The page could not perform this action.") }
        return result["result"]["value"]
    }
    private func literal(_ text: String) -> String { ConfigJSONValue.string(text).formatted }
    private struct WorkspaceBrowserSnapshot: Decodable {
        var url: String; var title: String; var visibleText: String; var elements: [WorkspaceBrowserElement]
    }
    private static let readScript = """
    (() => ({url:location.href,title:document.title,visibleText:(document.body?.innerText||'').slice(0,80000),
    elements:Array.from(document.querySelectorAll('a,button,input,textarea,select,[role=button]')).filter(e=>e.getClientRects().length).slice(0,150).map((e,i)=>{
    const selector=e.id?'#'+CSS.escape(e.id):'[data-sloppy-browser="'+i+'"]'; e.setAttribute('data-sloppy-browser',String(i));
    return {selector,role:e.getAttribute('role')||e.tagName.toLowerCase(),name:(e.getAttribute('aria-label')||e.innerText||e.getAttribute('placeholder')||'').slice(0,200),disabled:!!e.disabled};})}))()
    """
}
