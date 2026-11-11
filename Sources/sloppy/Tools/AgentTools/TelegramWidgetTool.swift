import AnyLanguageModel
import Foundation
import PluginSDK
import Protocols

struct TelegramWidgetSendTool: CoreTool {
    let name = "telegram.widget.send"
    let domain = "telegram"
    let title = "Send Telegram HTML widget"
    let status = "fully_functional"
    let description = "Send a compact offline HTML widget in the current explicitly-bound Telegram private chat. Not a browser: inline CSS/JS only, no network, text inputs or keyboard. HTML <=32768 UTF-8 bytes and zlib-9 <=4096 bytes. Required plain caption is the accessible summary. TelegramWidget.request(action) emits only registered symbolic actions (not approval/tool calls); its 'received' answer confirms transport receipt, not completion. Listen for chatDataChanged and render TelegramWidget.chatData. Code is immutable. Catch-all bindings are rejected; groups receive caption text only. Handles expire on restart or after 24h."
    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "html", description: "Self-contained Telegram widget HTML fragment, inline scripts/styles. No external resources.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "caption", description: "Required plain text summary, at most 1024 UTF-16 units.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "chatData", description: "Initial state string, at most 1024 UTF-8 bytes. Empty clears state.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "actions", description: "JSON array string of up to 32 unique allowed request tokens, each 1-64 UTF-8 bytes; [] disables requests.", schema: DynamicGenerationSchema(type: String.self)),
        ])
    }
    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let channel = context.channelID, context.sessionID == channel,
              let html = arguments["html"]?.asString, let caption = arguments["caption"]?.asString,
              let data = arguments["chatData"]?.asString,
              let json = arguments["actions"]?.asString, json.utf8.count <= 8192,
              let actions = try? JSONDecoder().decode([String].self, from: Data(json.utf8)),
              let service = context.projectService else {
            return toolFailure(tool: name, code: "invalid_context_or_arguments", message: "Requires a Telegram channel turn and html, caption, chatData, actions.", retryable: false)
        }
        do {
            let handle = try await service.sendTelegramWidget(channelID: channel,
                request: TelegramWidgetRequest(html: html, caption: caption, chatData: data, actions: actions))
            return toolSuccess(tool: name, data: .object(["handle": .string(handle), "textFallback": .bool(handle == "text_fallback")]))
        } catch {
            return toolFailure(tool: name, code: "widget_send_failed", message: String(describing: error), retryable: false)
        }
    }
}

struct TelegramWidgetUpdateTool: CoreTool {
    let name = "telegram.widget.update"
    let domain = "telegram"
    let title = "Update Telegram widget state"
    let status = "fully_functional"
    let description = "Update chatData of a widget sent by the current Telegram channel session. Use the opaque handle returned by telegram.widget.send; cannot change HTML, route, permissions or action tokens. State is <=1024 UTF-8 bytes, empty clears it."
    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "handle", description: "Opaque handle from send, not a Telegram message ID.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "chatData", description: "New state string <=1024 UTF-8 bytes.", schema: DynamicGenerationSchema(type: String.self)),
        ])
    }
    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let channel = context.channelID, context.sessionID == channel,
              let handle = arguments["handle"]?.asString, let data = arguments["chatData"]?.asString,
              let service = context.projectService else {
            return toolFailure(tool: name, code: "invalid_context_or_arguments", message: "Requires current Telegram channel context, handle and chatData.", retryable: false)
        }
        do {
            try await service.updateTelegramWidget(channelID: channel, handle: handle, chatData: data)
            return toolSuccess(tool: name, data: .object(["updated": .bool(true)]))
        } catch {
            return toolFailure(tool: name, code: "widget_update_failed", message: String(describing: error), retryable: false)
        }
    }
}
