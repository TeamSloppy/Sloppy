import AnyLanguageModel
import Foundation
import Protocols

private let workspaceElementInputSchema = DynamicGenerationSchema(
    name: "WorkspaceElementInput",
    properties: [
        .init(name: "id", description: "Stable element identifier.", schema: DynamicGenerationSchema(type: String.self)),
        .init(name: "kind", description: "sticky, text, shape, image, table, frame, or widget.", schema: DynamicGenerationSchema(type: String.self)),
        .init(name: "x", description: "Canvas X coordinate.", schema: DynamicGenerationSchema(type: Double.self)),
        .init(name: "y", description: "Canvas Y coordinate.", schema: DynamicGenerationSchema(type: Double.self)),
        .init(name: "width", description: "Element width.", schema: DynamicGenerationSchema(type: Double.self)),
        .init(name: "height", description: "Element height.", schema: DynamicGenerationSchema(type: Double.self)),
        .init(name: "text", description: "Visible text or Markdown.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
        .init(name: "artifactId", description: "Widget or image artifact identifier.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
        .init(name: "parentId", description: "Optional parent frame id.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
        .init(name: "groupId", description: "Optional group identifier.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
        .init(name: "zIndex", description: "Stacking order.", schema: DynamicGenerationSchema(type: Int.self), isOptional: true),
        .init(name: "revision", description: "Current element revision when updating.", schema: DynamicGenerationSchema(type: Int.self), isOptional: true),
        .init(name: "dataJson", description: "Optional JSON object with kind-specific structured data.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
        .init(name: "styleJson", description: "Optional JSON object with CSS-safe visual values.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
    ]
)

private let workspaceConnectionInputSchema = DynamicGenerationSchema(
    name: "WorkspaceConnectionInput",
    properties: [
        .init(name: "id", description: "Stable connection identifier.", schema: DynamicGenerationSchema(type: String.self)),
        .init(name: "sourceElementId", description: "Source element id.", schema: DynamicGenerationSchema(type: String.self)),
        .init(name: "targetElementId", description: "Target element id.", schema: DynamicGenerationSchema(type: String.self)),
        .init(name: "label", description: "Optional connector label.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
    ]
)

private let workspaceOperationInputSchema = DynamicGenerationSchema(
    name: "WorkspaceOperationInput",
    properties: [
        .init(name: "type", description: "Typed operation such as element.create, element.update, element.move, element.resize, element.group, element.ungroup, element.frame_assign, element.z_order, element.delete, element.connect, element.disconnect, or connection.update.", schema: DynamicGenerationSchema(type: String.self)),
        .init(name: "targetId", description: "Target id for delete operations.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
        .init(name: "element", description: "Element payload for create/update.", schema: workspaceElementInputSchema, isOptional: true),
        .init(name: "connection", description: "Connection payload for create/update.", schema: workspaceConnectionInputSchema, isOptional: true),
    ]
)

private let workspaceExpectedRevisionSchema = DynamicGenerationSchema(
    name: "WorkspaceExpectedRevision",
    properties: [
        .init(name: "elementId", description: "Element identifier.", schema: DynamicGenerationSchema(type: String.self)),
        .init(name: "revision", description: "Revision returned by workspace.get/query.", schema: DynamicGenerationSchema(type: Int.self)),
    ]
)

struct WorkspacesListTool: CoreTool {
    let domain = "workspace"
    let title = "List AI workspaces"
    let status = "fully_functional"
    let name = "workspaces.list"
    let description = "List canvas workspaces that this agent can access."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "projectId", description: "Optional linked project filter.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "includeArchived", description: "Include archived workspaces.", schema: DynamicGenerationSchema(type: Bool.self), isOptional: true),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let service = context.projectService else { return workspaceUnavailable(name) }
        let records = await service.listCanvasWorkspaces(
            principalKind: .agent,
            principalId: context.agentID,
            isAdmin: false,
            projectId: trimmedStringArgument(arguments, "projectId"),
            includeArchived: arguments["includeArchived"]?.asBool ?? false
        )
        return toolSuccess(tool: name, data: encodeJSONValue(records))
    }
}

struct WorkspacesCreateTool: CoreTool {
    let domain = "workspace"
    let title = "Create AI workspace"
    let status = "fully_functional"
    let name = "workspaces.create"
    let description = "Create a canvas workspace owned by the current agent, optionally from a template."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "title", description: "Workspace title.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "description", description: "Workspace purpose.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "projectId", description: "Optional linked project id.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "templateId", description: "Optional template id.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let service = context.projectService else { return workspaceUnavailable(name) }
        do {
            let record = try await service.createCanvasWorkspace(
                request: WorkspaceCreateRequest(
                    title: stringArgument(arguments, "title", default: ""),
                    description: trimmedStringArgument(arguments, "description"),
                    projectId: trimmedStringArgument(arguments, "projectId"),
                    templateId: trimmedStringArgument(arguments, "templateId")
                ),
                ownerKind: .agent,
                ownerId: context.agentID
            )
            return toolSuccess(tool: name, data: encodeJSONValue(record))
        } catch {
            return workspaceFailure(name, error)
        }
    }
}

struct WorkspaceGetTool: CoreTool {
    let domain = "workspace"
    let title = "Inspect AI workspace"
    let status = "fully_functional"
    let name = "workspace.get"
    let description = "Read workspace metadata and the canonical canvas document before editing it."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "workspaceId", description: "Workspace identifier.", schema: DynamicGenerationSchema(type: String.self)),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let service = context.projectService else { return workspaceUnavailable(name) }
        let workspaceId = stringArgument(arguments, "workspaceId", default: "")
        do {
            let record = try await service.getCanvasWorkspace(
                id: workspaceId,
                principalKind: .agent,
                principalId: context.agentID,
                isAdmin: false
            )
            let document = try await service.canvasWorkspaceDocument(
                id: workspaceId,
                principalKind: .agent,
                principalId: context.agentID,
                isAdmin: false
            )
            return toolSuccess(tool: name, data: .object([
                "workspace": encodeJSONValue(record),
                "document": encodeJSONValue(document),
            ]))
        } catch {
            return workspaceFailure(name, error)
        }
    }
}

struct WorkspaceUpdateTool: CoreTool {
    let domain = "workspace"
    let title = "Update AI workspace"
    let status = "fully_functional"
    let name = "workspace.update"
    let description = "Update workspace title, description, cover, or project link without changing canvas content."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "workspaceId", description: "Workspace identifier.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "title", description: "New title.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "description", description: "New description.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "cover", description: "New cover value.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "projectId", description: "Project to link.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "clearProject", description: "Remove the current project link.", schema: DynamicGenerationSchema(type: Bool.self), isOptional: true),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let service = context.projectService else { return workspaceUnavailable(name) }
        do {
            let record = try await service.updateCanvasWorkspace(
                id: stringArgument(arguments, "workspaceId", default: ""),
                request: WorkspaceUpdateRequest(
                    title: arguments["title"]?.asString,
                    description: arguments["description"]?.asString,
                    cover: arguments["cover"]?.asString,
                    projectId: arguments["projectId"]?.asString,
                    clearProject: arguments["clearProject"]?.asBool
                ),
                principalKind: .agent,
                principalId: context.agentID,
                isAdmin: false
            )
            return toolSuccess(tool: name, data: encodeJSONValue(record))
        } catch {
            return workspaceFailure(name, error)
        }
    }
}

struct WorkspaceElementsQueryTool: CoreTool {
    let domain = "workspace"
    let title = "Query workspace elements"
    let status = "fully_functional"
    let name = "workspace.elements.query"
    let description = "Query elements by id, kind, text, group, frame, or rectangular canvas region."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "workspaceId", description: "Workspace identifier.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "ids", description: "Optional element ids.", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)), isOptional: true),
            .init(name: "kind", description: "Optional element kind.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "text", description: "Case-insensitive text search.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "parentId", description: "Optional parent frame id.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "groupId", description: "Optional group id.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "minX", description: "Optional region left.", schema: DynamicGenerationSchema(type: Double.self), isOptional: true),
            .init(name: "minY", description: "Optional region top.", schema: DynamicGenerationSchema(type: Double.self), isOptional: true),
            .init(name: "maxX", description: "Optional region right.", schema: DynamicGenerationSchema(type: Double.self), isOptional: true),
            .init(name: "maxY", description: "Optional region bottom.", schema: DynamicGenerationSchema(type: Double.self), isOptional: true),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let service = context.projectService else { return workspaceUnavailable(name) }
        do {
            let document = try await service.canvasWorkspaceDocument(
                id: stringArgument(arguments, "workspaceId", default: ""),
                principalKind: .agent,
                principalId: context.agentID,
                isAdmin: false
            )
            let ids = Set(arguments["ids"]?.asArray?.compactMap(\.asString) ?? [])
            let requestedKind = arguments["kind"]?.asString.flatMap(WorkspaceElementKind.init(rawValue:))
            let text = arguments["text"]?.asString?.lowercased()
            let elements = document.elements.filter { element in
                let matchesText = text.map { jsonSearchText(element.data).contains($0) } ?? true
                return (ids.isEmpty || ids.contains(element.id))
                    && (requestedKind == nil || element.kind == requestedKind)
                    && (arguments["parentId"] == nil || element.parentId == arguments["parentId"]?.asString)
                    && (arguments["groupId"] == nil || element.groupId == arguments["groupId"]?.asString)
                    && matchesText
                    && regionContains(element.bounds, arguments: arguments)
            }
            return toolSuccess(tool: name, data: .object([
                "workspaceId": .string(document.workspaceId),
                "revision": .number(Double(document.revision)),
                "elements": encodeJSONValue(elements),
            ]))
        } catch {
            return workspaceFailure(name, error)
        }
    }
}

struct WorkspaceTransactionApplyTool: CoreTool {
    let domain = "workspace"
    let title = "Apply workspace transaction"
    let status = "fully_functional"
    let name = "workspace.transaction.apply"
    let description = "Atomically create, update, delete, move, resize, group, frame, connect, or reorder workspace content."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "workspaceId", description: "Workspace identifier.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "baseRevision", description: "Workspace revision returned by the latest read.", schema: DynamicGenerationSchema(type: Int.self)),
            .init(name: "summary", description: "Short human-readable change summary.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "expectedRevisions", description: "Required current revisions for every updated/deleted element.", schema: DynamicGenerationSchema(arrayOf: workspaceExpectedRevisionSchema), isOptional: true),
            .init(name: "operations", description: "Ordered atomic mutation operations.", schema: DynamicGenerationSchema(arrayOf: workspaceOperationInputSchema)),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let service = context.projectService else { return workspaceUnavailable(name) }
        let workspaceId = stringArgument(arguments, "workspaceId", default: "")
        do {
            let request = try workspaceTransactionRequest(arguments)
            await service.publishCanvasWorkspaceAgentStatus(
                workspaceId: workspaceId,
                agentId: context.agentID,
                status: "Applying \(request.summary ?? "workspace changes")"
            )
            let committed = try await service.commitCanvasWorkspaceTransaction(
                workspaceId: workspaceId,
                request: request,
                actor: WorkspaceActor(kind: .agent, id: context.agentID, displayName: context.agentID),
                isAdmin: false
            )
            await service.publishCanvasWorkspaceAgentStatus(
                workspaceId: workspaceId,
                agentId: context.agentID,
                status: "Completed \(request.summary ?? "workspace changes")"
            )
            return toolSuccess(tool: name, data: encodeJSONValue(committed))
        } catch {
            await service.publishCanvasWorkspaceAgentStatus(
                workspaceId: workspaceId,
                agentId: context.agentID,
                status: "Workspace change failed"
            )
            return workspaceFailure(name, error)
        }
    }
}

struct WorkspaceTemplateListTool: CoreTool {
    let domain = "workspace"
    let title = "List workspace templates"
    let status = "fully_functional"
    let name = "workspace.template.list"
    let description = "List built-in, team, and personal canvas templates available to this agent."
    var parameters: GenerationSchema { .objectSchema([]) }

    func invoke(arguments _: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let service = context.projectService else { return workspaceUnavailable(name) }
        return toolSuccess(tool: name, data: encodeJSONValue(await service.workspaceTemplates(principalId: context.agentID)))
    }
}

struct WorkspaceTemplateApplyTool: CoreTool {
    let domain = "workspace"
    let title = "Apply workspace template"
    let status = "fully_functional"
    let name = "workspace.template.apply"
    let description = "Place a remapped template fragment into a workspace as one atomic transaction."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "workspaceId", description: "Workspace identifier.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "templateId", description: "Template identifier.", schema: DynamicGenerationSchema(type: String.self)),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let service = context.projectService else { return workspaceUnavailable(name) }
        do {
            let committed = try await service.applyWorkspaceTemplate(
                workspaceId: stringArgument(arguments, "workspaceId", default: ""),
                templateId: stringArgument(arguments, "templateId", default: ""),
                actor: WorkspaceActor(kind: .agent, id: context.agentID, displayName: context.agentID),
                isAdmin: false
            )
            return toolSuccess(tool: name, data: encodeJSONValue(committed))
        } catch {
            return workspaceFailure(name, error)
        }
    }
}

struct WorkspaceTemplateSaveTool: CoreTool {
    let domain = "workspace"
    let title = "Save workspace template"
    let status = "fully_functional"
    let name = "workspace.template.save"
    let description = "Save the complete current workspace document as a personal or team template."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "workspaceId", description: "Source workspace identifier.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "title", description: "Template title.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "description", description: "Template description.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "category", description: "Template category.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "visibility", description: "personal or team.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let service = context.projectService else { return workspaceUnavailable(name) }
        do {
            let workspaceId = stringArgument(arguments, "workspaceId", default: "")
            let document = try await service.canvasWorkspaceDocument(
                id: workspaceId,
                principalKind: .agent,
                principalId: context.agentID,
                isAdmin: false
            )
            let visibility = WorkspaceTemplateVisibility(
                rawValue: stringArgument(arguments, "visibility", default: "personal")
            ) ?? .personal
            let template = try await service.createWorkspaceTemplate(
                request: WorkspaceTemplateCreateRequest(
                    title: stringArgument(arguments, "title", default: ""),
                    description: stringArgument(arguments, "description", default: ""),
                    category: stringArgument(arguments, "category", default: "custom"),
                    visibility: visibility,
                    document: document
                ),
                ownerId: context.agentID
            )
            return toolSuccess(tool: name, data: encodeJSONValue(template))
        } catch {
            return workspaceFailure(name, error)
        }
    }
}

struct WorkspaceArtifactPlaceTool: CoreTool {
    let domain = "workspace"
    let title = "Place artifact in workspace"
    let status = "fully_functional"
    let name = "workspace.artifact.place"
    let description = "Place an existing widget or image artifact on the canvas."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "workspaceId", description: "Workspace identifier.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "artifactId", description: "Existing artifact identifier.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "baseRevision", description: "Latest workspace revision.", schema: DynamicGenerationSchema(type: Int.self)),
            .init(name: "x", description: "Canvas X coordinate.", schema: DynamicGenerationSchema(type: Double.self)),
            .init(name: "y", description: "Canvas Y coordinate.", schema: DynamicGenerationSchema(type: Double.self)),
            .init(name: "width", description: "Widget width.", schema: DynamicGenerationSchema(type: Double.self), isOptional: true),
            .init(name: "height", description: "Widget height.", schema: DynamicGenerationSchema(type: Double.self), isOptional: true),
            .init(name: "title", description: "Visible widget title.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let service = context.projectService else { return workspaceUnavailable(name) }
        let artifactId = stringArgument(arguments, "artifactId", default: "")
        let element = WorkspaceElement(
            id: "element-\(UUID().uuidString.lowercased())",
            kind: .widget,
            bounds: WorkspaceRect(
                x: arguments["x"]?.asNumber ?? 0,
                y: arguments["y"]?.asNumber ?? 0,
                width: arguments["width"]?.asNumber ?? 360,
                height: arguments["height"]?.asNumber ?? 240
            ),
            data: [
                "artifactId": .string(artifactId),
                "text": .string(stringArgument(arguments, "title", default: "Widget")),
            ]
        )
        do {
            let committed = try await service.commitCanvasWorkspaceTransaction(
                workspaceId: stringArgument(arguments, "workspaceId", default: ""),
                request: WorkspaceTransactionRequest(
                    id: "artifact-\(UUID().uuidString.lowercased())",
                    baseRevision: arguments["baseRevision"]?.asInt ?? 0,
                    operations: [WorkspaceOperation(kind: .createElement, element: element)],
                    summary: "Place artifact \(artifactId)"
                ),
                actor: WorkspaceActor(kind: .agent, id: context.agentID, displayName: context.agentID),
                isAdmin: false
            )
            return toolSuccess(tool: name, data: encodeJSONValue(committed))
        } catch {
            return workspaceFailure(name, error)
        }
    }
}

private func workspaceTransactionRequest(_ arguments: [String: JSONValue]) throws -> WorkspaceTransactionRequest {
    let expected = Dictionary(uniqueKeysWithValues: (arguments["expectedRevisions"]?.asArray ?? []).compactMap { value -> (String, Int)? in
        guard let object = value.asObject,
              let id = object["elementId"]?.asString,
              let revision = object["revision"]?.asInt
        else {
            return nil
        }
        return (id, revision)
    })
    let operations = try (arguments["operations"]?.asArray ?? []).map(parseWorkspaceOperation)
    return WorkspaceTransactionRequest(
        id: "agent-\(UUID().uuidString.lowercased())",
        baseRevision: arguments["baseRevision"]?.asInt ?? 0,
        expectedElementRevisions: expected,
        operations: operations,
        summary: arguments["summary"]?.asString
    )
}

private func parseWorkspaceOperation(_ value: JSONValue) throws -> WorkspaceOperation {
    guard let object = value.asObject,
          let rawKind = object["type"]?.asString,
          let kind = WorkspaceOperationKind(rawValue: rawKind)
    else {
        throw CoreService.WorkspaceError.invalidPayload
    }
    return WorkspaceOperation(
        kind: kind,
        element: try object["element"].map(parseWorkspaceElement),
        connection: try object["connection"].map(parseWorkspaceConnection),
        targetId: object["targetId"]?.asString
    )
}

private func parseWorkspaceElement(_ value: JSONValue) throws -> WorkspaceElement {
    guard let object = value.asObject,
          let id = object["id"]?.asString,
          let rawKind = object["kind"]?.asString,
          let kind = WorkspaceElementKind(rawValue: rawKind)
    else {
        throw CoreService.WorkspaceError.invalidPayload
    }
    var data = decodeJSONObject(object["dataJson"]?.asString) ?? [:]
    if let text = object["text"]?.asString { data["text"] = .string(text) }
    if let artifactId = object["artifactId"]?.asString { data["artifactId"] = .string(artifactId) }
    return WorkspaceElement(
        id: id,
        kind: kind,
        bounds: WorkspaceRect(
            x: object["x"]?.asNumber ?? 0,
            y: object["y"]?.asNumber ?? 0,
            width: object["width"]?.asNumber ?? 240,
            height: object["height"]?.asNumber ?? 160
        ),
        zIndex: object["zIndex"]?.asInt ?? 0,
        parentId: object["parentId"]?.asString,
        groupId: object["groupId"]?.asString,
        style: decodeJSONObject(object["styleJson"]?.asString) ?? [:],
        data: data,
        revision: object["revision"]?.asInt ?? 0
    )
}

private func parseWorkspaceConnection(_ value: JSONValue) throws -> WorkspaceConnection {
    guard let object = value.asObject,
          let id = object["id"]?.asString,
          let source = object["sourceElementId"]?.asString,
          let target = object["targetElementId"]?.asString
    else {
        throw CoreService.WorkspaceError.invalidPayload
    }
    return WorkspaceConnection(
        id: id,
        sourceElementId: source,
        targetElementId: target,
        label: object["label"]?.asString
    )
}

private func decodeJSONObject(_ value: String?) -> [String: JSONValue]? {
    guard let value, let data = value.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode([String: JSONValue].self, from: data)
}

private func jsonSearchText(_ value: [String: JSONValue]) -> String {
    guard let data = try? JSONEncoder().encode(value),
          let text = String(data: data, encoding: .utf8)
    else {
        return ""
    }
    return text.lowercased()
}

private func regionContains(_ bounds: WorkspaceRect, arguments: [String: JSONValue]) -> Bool {
    if let minX = arguments["minX"]?.asNumber, bounds.x + bounds.width < minX { return false }
    if let minY = arguments["minY"]?.asNumber, bounds.y + bounds.height < minY { return false }
    if let maxX = arguments["maxX"]?.asNumber, bounds.x > maxX { return false }
    if let maxY = arguments["maxY"]?.asNumber, bounds.y > maxY { return false }
    return true
}

private func workspaceUnavailable(_ tool: String) -> ToolInvocationResult {
    toolFailure(tool: tool, code: "not_available", message: "Workspace service is unavailable.", retryable: false)
}

private func workspaceFailure(_ tool: String, _ error: Error) -> ToolInvocationResult {
    guard let error = error as? CoreService.WorkspaceError else {
        return toolFailure(tool: tool, code: "workspace_failed", message: error.localizedDescription, retryable: true)
    }
    switch error {
    case .invalidID, .invalidPayload:
        return toolFailure(tool: tool, code: "invalid_arguments", message: "Workspace payload is invalid.", retryable: false)
    case .notFound:
        return toolFailure(tool: tool, code: "workspace_not_found", message: "Workspace was not found.", retryable: false)
    case .forbidden:
        return toolFailure(tool: tool, code: "workspace_forbidden", message: "The agent does not have access to this workspace.", retryable: false)
    case .conflict(let revision, let ids):
        return ToolInvocationResult(
            tool: tool,
            ok: false,
            data: .object([
                "latestRevision": .number(Double(revision)),
                "conflictElementIds": .array(ids.map(JSONValue.string)),
            ]),
            error: ToolErrorPayload(
                code: "workspace_conflict",
                message: "Workspace changed concurrently. Read the conflicting elements and retry explicitly.",
                retryable: true
            )
        )
    }
}
