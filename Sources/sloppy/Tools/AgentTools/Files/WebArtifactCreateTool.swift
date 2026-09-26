import AnyLanguageModel
import Foundation
import Protocols

/// Creates a self-contained visual that can be referenced from a chat transcript.
struct WebArtifactCreateTool: CoreTool {
    let domain = "artifacts"
    let title = "Create web visual artifact"
    let status = "fully_functional"
    let name = "artifacts.web.create"
    let description = "Create a durable, self-contained HTML visual for a chat answer. Each call creates a new artifact so earlier chat links keep their original content. Use this when the user explicitly requests a web visual or when meaningful interaction with the visual is needed to understand the answer."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "html", description: "Complete, self-contained HTML document. Do not load external resources.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "title", description: "Short title shown on the artifact card.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "summary", description: "One sentence explaining what the visual shows.", schema: DynamicGenerationSchema(type: String.self)),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let html = arguments["html"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = arguments["title"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let summary = arguments["summary"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty, !summary.isEmpty, !html.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`html`, `title`, and `summary` are required.", retryable: false)
        }
        guard title.count <= 120, summary.count <= 500, html.utf8.count <= 2 * 1024 * 1024 else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "Web visual title, summary, or HTML exceeds its size limit.", retryable: false)
        }

        let size = WidgetArtifactService.Size(name: "web", width: 1024, height: 640)
        do {
            try WidgetArtifactService.validate(html: html)
        } catch WidgetArtifactService.WidgetError.invalidHTML {
            return toolFailure(tool: name, code: "invalid_arguments", message: "The visual must include a full HTML document.", retryable: false)
        } catch WidgetArtifactService.WidgetError.externalResource {
            return toolFailure(tool: name, code: "invalid_arguments", message: "The visual must be self-contained and must not load external resources.", retryable: false)
        } catch {
            return toolFailure(tool: name, code: "invalid_arguments", message: error.localizedDescription, retryable: false)
        }

        let id = UUID().uuidString
        do {
            try WidgetArtifactService.writeBundle(
                id: id,
                prompt: summary,
                html: html,
                size: size,
                currentRootURL: context.workspaceRootURL
            )
        } catch {
            return toolFailure(tool: name, code: "write_failed", message: error.localizedDescription, retryable: true)
        }

        let record = PersistedArtifactRecord(
            id: id,
            title: title,
            kind: "widget",
            mediaType: "text/html",
            content: html,
            previewText: summary,
            widgetSize: size.name,
            widgetWidth: size.width,
            widgetHeight: size.height,
            widgetEntry: WidgetArtifactService.entryFileName,
            bundlePath: WidgetArtifactService.bundlePath(id: id),
            createdAt: Date()
        )
        await context.store.persistArtifact(record: record)

        return toolSuccess(tool: name, data: .object([
            "artifact": .object([
                "id": .string(record.id),
                "title": .string(record.title),
                "kind": .string(record.kind),
                "mediaType": .string(record.mediaType),
                "previewText": .string(summary),
                "webUrl": .string("/artifacts/\(record.id)"),
                "createdAt": .string(ISO8601DateFormatter().string(from: record.createdAt)),
            ]),
        ]))
    }
}
