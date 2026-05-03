import AnyLanguageModel
import Foundation
import Protocols

struct BrowserOpenTool: CoreTool {
    let domain = "browser"
    let title = "Open browser"
    let status = "preview"
    let name = "browser.open"
    let description = "Launch or reuse the configured Chromium/CDP browser with the managed profile and optionally open a URL."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "url", description: "Optional URL to open. Defaults to about:blank.", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        await browserResult(tool: name) {
            try await context.browserService.open(sessionID: context.sessionID, url: arguments["url"]?.asString)
        }
    }
}

struct BrowserNavigateTool: CoreTool {
    let domain = "browser"
    let title = "Navigate browser"
    let status = "preview"
    let name = "browser.navigate"
    let description = "Navigate a browser page by URL using the configured Chromium/CDP browser."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "url", description: "URL to navigate to.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "pageId", description: "Optional page ID. Defaults to the current page.", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let url = arguments["url"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !url.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`url` is required.", retryable: false)
        }
        return await browserResult(tool: name) {
            try await context.browserService.navigate(
                sessionID: context.sessionID,
                pageID: arguments["pageId"]?.asString,
                url: url
            )
        }
    }
}

struct BrowserClickTool: CoreTool {
    let domain = "browser"
    let title = "Click browser selector"
    let status = "preview"
    let name = "browser.click"
    let description = "Click an element in the browser by CSS selector using CDP."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "selector", description: "CSS selector to click.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "pageId", description: "Optional page ID. Defaults to the current page.", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let selector = arguments["selector"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !selector.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`selector` is required.", retryable: false)
        }
        return await browserResult(tool: name) {
            try await context.browserService.click(
                sessionID: context.sessionID,
                pageID: arguments["pageId"]?.asString,
                selector: selector
            )
        }
    }
}

struct BrowserTypeTool: CoreTool {
    let domain = "browser"
    let title = "Type in browser selector"
    let status = "preview"
    let name = "browser.type"
    let description = "Focus an element by CSS selector and insert text using CDP."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "selector", description: "CSS selector to focus.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "text", description: "Text to insert.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "pageId", description: "Optional page ID. Defaults to the current page.", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let selector = arguments["selector"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !selector.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`selector` is required.", retryable: false)
        }
        let text = arguments["text"]?.asString ?? ""
        guard !text.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`text` is required.", retryable: false)
        }
        return await browserResult(tool: name) {
            try await context.browserService.type(
                sessionID: context.sessionID,
                pageID: arguments["pageId"]?.asString,
                selector: selector,
                text: text
            )
        }
    }
}

struct BrowserScreenshotTool: CoreTool {
    let domain = "browser"
    let title = "Capture browser screenshot"
    let status = "preview"
    let name = "browser.screenshot"
    let description = "Capture a PNG screenshot of a browser page using CDP."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "outputPath", description: "Optional output file path. Defaults to a temporary PNG.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "pageId", description: "Optional page ID. Defaults to the current page.", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let outputPath = arguments["outputPath"]?.asString.flatMap { raw -> String? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return nil
            }
            if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
                return trimmed
            }
            return context.currentDirectoryURL.appendingPathComponent(trimmed).path
        }
        return await browserResult(tool: name) {
            try await context.browserService.screenshot(
                sessionID: context.sessionID,
                pageID: arguments["pageId"]?.asString,
                outputPath: outputPath
            )
        }
    }
}

struct BrowserStatusTool: CoreTool {
    let domain = "browser"
    let title = "Browser status"
    let status = "preview"
    let name = "browser.status"
    let description = "Return the configured browser automation status for the current agent session."

    var parameters: GenerationSchema {
        .objectSchema([])
    }

    func invoke(arguments _: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let payload = await context.browserService.status(sessionID: context.sessionID)
        return toolSuccess(tool: name, data: payload)
    }
}

struct BrowserCloseTool: CoreTool {
    let domain = "browser"
    let title = "Close browser"
    let status = "preview"
    let name = "browser.close"
    let description = "Close a browser page or the whole browser session."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "pageId", description: "Optional page ID. If omitted, closes the whole browser session.", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        await browserResult(tool: name) {
            try await context.browserService.close(sessionID: context.sessionID, pageID: arguments["pageId"]?.asString)
        }
    }
}

private func browserResult(tool: String, operation: () async throws -> JSONValue) async -> ToolInvocationResult {
    do {
        return toolSuccess(tool: tool, data: try await operation())
    } catch let error as BrowserCDPError {
        return toolFailure(tool: tool, code: error.code, message: error.localizedDescription, retryable: false)
    } catch {
        return toolFailure(tool: tool, code: "browser_failed", message: error.localizedDescription, retryable: true)
    }
}
