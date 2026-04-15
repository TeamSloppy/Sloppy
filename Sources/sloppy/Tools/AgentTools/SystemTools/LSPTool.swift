import AnyLanguageModel
import Foundation
import LanguageServerProtocol
import Protocols

// MARK: - LSPTool

struct LSPTool: CoreTool {
    let domain = "lsp"
    let title = "Code intelligence"
    let status = "fully_functional"
    let name = "lsp.query"
    let description = "Query language servers for code intelligence: definitions, references, hover docs, symbols, call hierarchy."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(
                name: "operation",
                description: "Operation to perform: goToDefinition, findReferences, hover, documentSymbol, workspaceSymbol, goToImplementation, prepareCallHierarchy, incomingCalls, outgoingCalls",
                schema: DynamicGenerationSchema(type: String.self)
            ),
            .init(
                name: "filePath",
                description: "Absolute or workspace-relative path to the file",
                schema: DynamicGenerationSchema(type: String.self),
                isOptional: true
            ),
            .init(
                name: "line",
                description: "1-based line number",
                schema: DynamicGenerationSchema(type: Int.self),
                isOptional: true
            ),
            .init(
                name: "character",
                description: "1-based character (column) offset",
                schema: DynamicGenerationSchema(type: Int.self),
                isOptional: true
            ),
            .init(
                name: "query",
                description: "Search query for workspaceSymbol operation",
                schema: DynamicGenerationSchema(type: String.self),
                isOptional: true
            ),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        let opRaw = arguments["operation"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let operation = LSPOperation(rawValue: opRaw) else {
            return toolFailure(
                tool: name,
                code: "invalid_operation",
                message: "Unknown operation '\(opRaw)'. Valid values: \(LSPOperation.allCases.map(\.rawValue).joined(separator: ", ")).",
                retryable: false
            )
        }

        guard let lspManager = context.lspManager else {
            return toolFailure(tool: name, code: "lsp_not_configured", message: "LSP is not configured.", retryable: false)
        }

        if operation == .workspaceSymbol {
            return await invokeWorkspaceSymbol(arguments: arguments, lspManager: lspManager)
        }

        let rawPath = arguments["filePath"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawPath.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`filePath` is required.", retryable: false)
        }

        let filePath = context.resolveFilePath(rawPath)
        let fileURL = URL(fileURLWithPath: filePath)
        let uri = DocumentURI(fileURL)

        do {
            let instance = try await lspManager.instance(for: filePath)
            try await instance.openFileIfNeeded(uri: uri, filePath: filePath)
            return try await dispatch(
                operation: operation,
                uri: uri,
                arguments: arguments,
                instance: instance,
                filePath: filePath
            )
        } catch let error as LSPServerError {
            return toolFailure(tool: name, code: "lsp_error", message: error.localizedDescription, retryable: false)
        } catch {
            return toolFailure(tool: name, code: "lsp_error", message: error.localizedDescription, retryable: true)
        }
    }

    // MARK: - Dispatch

    private func dispatch(
        operation: LSPOperation,
        uri: DocumentURI,
        arguments: [String: JSONValue],
        instance: LSPServerInstance,
        filePath: String
    ) async throws -> ToolInvocationResult {
        switch operation {
        case .goToDefinition:
            let position = try requirePosition(arguments: arguments)
            let result = try await instance.definition(uri: uri, position: position)
            return formatLocationsOrLinks(result, filePath: filePath)

        case .findReferences:
            let position = try requirePosition(arguments: arguments)
            let result = try await instance.references(uri: uri, position: position)
            return formatLocations(result)

        case .hover:
            let position = try requirePosition(arguments: arguments)
            let result = try await instance.hover(uri: uri, position: position)
            return formatHover(result)

        case .documentSymbol:
            let result = try await instance.documentSymbol(uri: uri)
            return formatDocumentSymbol(result, filePath: filePath)

        case .goToImplementation:
            let position = try requirePosition(arguments: arguments)
            let result = try await instance.implementation(uri: uri, position: position)
            return formatLocationsOrLinks(result, filePath: filePath)

        case .prepareCallHierarchy:
            let position = try requirePosition(arguments: arguments)
            let result = try await instance.prepareCallHierarchy(uri: uri, position: position)
            return formatCallHierarchyItems(result)

        case .incomingCalls:
            let position = try requirePosition(arguments: arguments)
            let result = try await instance.incomingCalls(uri: uri, position: position)
            return formatIncomingCalls(result)

        case .outgoingCalls:
            let position = try requirePosition(arguments: arguments)
            let result = try await instance.outgoingCalls(uri: uri, position: position)
            return formatOutgoingCalls(result)

        case .workspaceSymbol:
            fatalError("unreachable — handled before dispatch")
        }
    }

    private func invokeWorkspaceSymbol(
        arguments: [String: JSONValue],
        lspManager: LSPServerManager
    ) async -> ToolInvocationResult {
        let query = arguments["query"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let filePath = arguments["filePath"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !filePath.isEmpty else {
            return toolFailure(
                tool: name,
                code: "invalid_arguments",
                message: "`filePath` is required to route to the correct language server.",
                retryable: false
            )
        }

        do {
            let instance = try await lspManager.instance(for: filePath)
            let result = try await instance.workspaceSymbol(query: query)
            return formatWorkspaceSymbols(result)
        } catch let error as LSPServerError {
            return toolFailure(tool: name, code: "lsp_error", message: error.localizedDescription, retryable: false)
        } catch {
            return toolFailure(tool: name, code: "lsp_error", message: error.localizedDescription, retryable: true)
        }
    }

    // MARK: - Position helpers

    private func requirePosition(arguments: [String: JSONValue]) throws -> Position {
        guard let line = arguments["line"]?.asInt, let character = arguments["character"]?.asInt else {
            throw LSPToolError.missingPosition
        }
        // Convert from 1-based (agent-facing) to 0-based (LSP)
        return Position(line: max(0, line - 1), utf16index: max(0, character - 1))
    }

    // MARK: - Result formatters

    private func formatLocationsOrLinks(
        _ response: LocationsOrLocationLinksResponse?,
        filePath: String
    ) -> ToolInvocationResult {
        let locations: [Location]
        switch response {
        case .locations(let locs):
            locations = locs
        case .locationLinks(let links):
            locations = links.map { Location(uri: $0.targetUri, range: $0.targetRange) }
        case nil:
            locations = []
        }
        return toolSuccess(tool: name, data: .object([
            "count": .number(Double(locations.count)),
            "locations": .array(locations.map(jsonLocation))
        ]))
    }

    private func formatLocations(_ locations: [Location]) -> ToolInvocationResult {
        toolSuccess(tool: name, data: .object([
            "count": .number(Double(locations.count)),
            "locations": .array(locations.map(jsonLocation))
        ]))
    }

    private func formatHover(_ response: HoverResponse?) -> ToolInvocationResult {
        guard let response else {
            return toolSuccess(tool: name, data: .object(["content": .null]))
        }
        let content: String
        switch response.contents {
        case .markupContent(let markup):
            content = markup.value
        case .markedStrings(let strings):
            content = strings.map { s in
                switch s {
                case .markdown(let v): return v
                case .codeBlock(_, let v): return v
                }
            }.joined(separator: "\n")
        }
        return toolSuccess(tool: name, data: .object(["content": .string(content)]))
    }

    private func formatDocumentSymbol(_ response: DocumentSymbolResponse?, filePath: String) -> ToolInvocationResult {
        switch response {
        case .documentSymbols(let symbols):
            return toolSuccess(tool: name, data: .object([
                "count": .number(Double(symbols.count)),
                "symbols": .array(symbols.map { jsonDocumentSymbol($0, uri: filePath) })
            ]))
        case .symbolInformation(let infos):
            return toolSuccess(tool: name, data: .object([
                "count": .number(Double(infos.count)),
                "symbols": .array(infos.map(jsonSymbolInformation))
            ]))
        case nil:
            return toolSuccess(tool: name, data: .object(["count": .number(0), "symbols": .array([])]))
        }
    }

    private func formatWorkspaceSymbols(_ items: [WorkspaceSymbolItem]) -> ToolInvocationResult {
        toolSuccess(tool: name, data: .object([
            "count": .number(Double(items.count)),
            "symbols": .array(items.map(jsonWorkspaceSymbolItem))
        ]))
    }

    private func formatCallHierarchyItems(_ items: [CallHierarchyItem]) -> ToolInvocationResult {
        toolSuccess(tool: name, data: .object([
            "count": .number(Double(items.count)),
            "items": .array(items.map(jsonCallHierarchyItem))
        ]))
    }

    private func formatIncomingCalls(_ calls: [CallHierarchyIncomingCall]) -> ToolInvocationResult {
        toolSuccess(tool: name, data: .object([
            "count": .number(Double(calls.count)),
            "calls": .array(calls.map { call in
                .object([
                    "from": jsonCallHierarchyItem(call.from),
                    "fromRangesCount": .number(Double(call.fromRanges.count))
                ])
            })
        ]))
    }

    private func formatOutgoingCalls(_ calls: [CallHierarchyOutgoingCall]) -> ToolInvocationResult {
        toolSuccess(tool: name, data: .object([
            "count": .number(Double(calls.count)),
            "calls": .array(calls.map { call in
                .object([
                    "to": jsonCallHierarchyItem(call.to),
                    "fromRangesCount": .number(Double(call.fromRanges.count))
                ])
            })
        ]))
    }

    // MARK: - JSON helpers

    private func jsonLocation(_ loc: Location) -> JSONValue {
        .object([
            "uri": .string(loc.uri.stringValue),
            "line": .number(Double(loc.range.lowerBound.line + 1)),
            "character": .number(Double(loc.range.lowerBound.utf16index + 1)),
            "endLine": .number(Double(loc.range.upperBound.line + 1)),
            "endCharacter": .number(Double(loc.range.upperBound.utf16index + 1))
        ])
    }

    private func jsonCallHierarchyItem(_ item: CallHierarchyItem) -> JSONValue {
        .object([
            "name": .string(item.name),
            "kind": .string(item.kind.rawValue.description),
            "detail": item.detail.map(JSONValue.string) ?? .null,
            "uri": .string(item.uri.stringValue),
            "line": .number(Double(item.selectionRange.lowerBound.line + 1)),
            "character": .number(Double(item.selectionRange.lowerBound.utf16index + 1))
        ])
    }

    private func jsonDocumentSymbol(_ symbol: DocumentSymbol, uri: String) -> JSONValue {
        var obj: [String: JSONValue] = [
            "name": .string(symbol.name),
            "kind": .string(symbol.kind.rawValue.description),
            "line": .number(Double(symbol.selectionRange.lowerBound.line + 1)),
            "character": .number(Double(symbol.selectionRange.lowerBound.utf16index + 1))
        ]
        if let detail = symbol.detail { obj["detail"] = .string(detail) }
        if let children = symbol.children, !children.isEmpty {
            obj["children"] = .array(children.map { jsonDocumentSymbol($0, uri: uri) })
        }
        return .object(obj)
    }

    private func jsonSymbolInformation(_ info: SymbolInformation) -> JSONValue {
        var obj: [String: JSONValue] = [
            "name": .string(info.name),
            "kind": .string(info.kind.rawValue.description),
            "uri": .string(info.location.uri.stringValue),
            "line": .number(Double(info.location.range.lowerBound.line + 1)),
            "character": .number(Double(info.location.range.lowerBound.utf16index + 1))
        ]
        if let container = info.containerName { obj["containerName"] = .string(container) }
        return .object(obj)
    }

    private func jsonWorkspaceSymbolItem(_ item: WorkspaceSymbolItem) -> JSONValue {
        switch item {
        case .symbolInformation(let info):
            return jsonSymbolInformation(info)
        case .workspaceSymbol(let sym):
            var obj: [String: JSONValue] = [
                "name": .string(sym.name),
                "kind": .string(sym.kind.rawValue.description)
            ]
            if let container = sym.containerName { obj["containerName"] = .string(container) }
            switch sym.location {
            case .location(let loc):
                obj["uri"] = .string(loc.uri.stringValue)
                obj["line"] = .number(Double(loc.range.lowerBound.line + 1))
                obj["character"] = .number(Double(loc.range.lowerBound.utf16index + 1))
            case .uri(let u):
                obj["uri"] = .string(u.uri.stringValue)
            }
            return .object(obj)
        }
    }
}

// MARK: - LSPOperation

enum LSPOperation: String, CaseIterable {
    case goToDefinition
    case findReferences
    case hover
    case documentSymbol
    case workspaceSymbol
    case goToImplementation
    case prepareCallHierarchy
    case incomingCalls
    case outgoingCalls
}

// MARK: - LSPToolError

private enum LSPToolError: Error {
    case missingPosition
}

extension LSPToolError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingPosition:
            return "`line` and `character` are required for this operation."
        }
    }
}

// MARK: - ToolContext extension

private extension ToolContext {
    func resolveFilePath(_ raw: String) -> String {
        if raw.hasPrefix("/") { return raw }
        return currentDirectoryURL.appendingPathComponent(raw).path
    }
}
