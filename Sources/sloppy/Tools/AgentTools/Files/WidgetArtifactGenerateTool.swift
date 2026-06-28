import AnyLanguageModel
import Foundation
import Protocols

struct WidgetArtifactGenerateTool: CoreTool {
    let domain = "artifacts"
    let title = "Generate widget artifact"
    let status = "fully_functional"
    let name = "artifacts.widget.generate"
    let description = "Create or update a self-contained start-page widget artifact and persist it under `.sloppy/artifacts/widgets`."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "html", description: "Full self-contained widget HTML document.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "size", description: "Widget size: `small`, `medium`, or `large`.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "prompt", description: "Short summary of the widget intent for artifact metadata.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "artifactId", description: "Optional existing widget artifact id to update in place.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "title", description: "Optional explicit artifact title.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let prompt = arguments["prompt"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let html = arguments["html"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sizeValue = arguments["size"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let requestedArtifactID = arguments["artifactId"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedTitle = arguments["title"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !prompt.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`prompt` is required.", retryable: false)
        }
        guard !html.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`html` is required.", retryable: false)
        }

        let size: WidgetArtifactService.Size
        do {
            size = try WidgetArtifactService.size(named: sizeValue)
            try WidgetArtifactService.validate(html: html)
        } catch WidgetArtifactService.WidgetError.invalidSize {
            return toolFailure(tool: name, code: "invalid_arguments", message: "Invalid widget size.", retryable: false)
        } catch WidgetArtifactService.WidgetError.invalidHTML {
            return toolFailure(tool: name, code: "invalid_arguments", message: "Widget HTML must include a full HTML document.", retryable: false)
        } catch WidgetArtifactService.WidgetError.externalResource {
            return toolFailure(tool: name, code: "invalid_arguments", message: "Widget HTML must be self-contained and must not load external resources.", retryable: false)
        } catch {
            return toolFailure(tool: name, code: "invalid_arguments", message: error.localizedDescription, retryable: false)
        }

        let existingRecord: PersistedArtifactRecord?
        if let requestedArtifactID, !requestedArtifactID.isEmpty {
            existingRecord = await context.store.persistedArtifact(id: requestedArtifactID)
            if let existingRecord, existingRecord.kind != "widget" {
                return toolFailure(tool: name, code: "invalid_arguments", message: "Only widget artifacts can be updated with this tool.", retryable: false)
            }
        } else {
            existingRecord = nil
        }

        let artifactID = existingRecord?.id ?? UUID().uuidString
        let title = (requestedTitle?.isEmpty == false ? requestedTitle : nil)
            ?? existingRecord?.title
            ?? String(prompt.prefix(48))
        let createdAt = existingRecord?.createdAt ?? Date()

        do {
            try WidgetArtifactService.writeBundle(
                id: artifactID,
                prompt: prompt,
                html: html,
                size: size,
                currentRootURL: context.workspaceRootURL
            )
        } catch {
            return toolFailure(tool: name, code: "write_failed", message: error.localizedDescription, retryable: true)
        }

        let record = PersistedArtifactRecord(
            id: artifactID,
            title: title,
            kind: "widget",
            mediaType: "text/html",
            content: html,
            previewText: String(prompt.prefix(160)),
            widgetSize: size.name,
            widgetWidth: size.width,
            widgetHeight: size.height,
            widgetEntry: WidgetArtifactService.entryFileName,
            bundlePath: WidgetArtifactService.bundlePath(id: artifactID),
            createdAt: createdAt
        )
        await context.store.persistArtifact(record: record)

        return toolSuccess(tool: name, data: .object([
            "artifact": .object([
                "id": .string(record.id),
                "title": .string(record.title),
                "kind": .string(record.kind),
                "mediaType": .string(record.mediaType),
                "createdAt": .string(ISO8601DateFormatter().string(from: record.createdAt)),
                "previewText": .string(record.previewText ?? ""),
                "widget": .object([
                    "size": .string(size.name),
                    "width": .number(Double(size.width)),
                    "height": .number(Double(size.height)),
                    "entry": .string(WidgetArtifactService.entryFileName),
                ]),
            ]),
        ]))
    }
}
