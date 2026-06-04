import Foundation
import Protocols

final class WorkflowDefinitionFileStore {
    enum StoreError: Error, Equatable {
        case invalidPayload
        case notFound
        case storageFailure
    }

    private let fileManager: FileManager
    private var workspaceRootURL: URL

    init(workspaceRootURL: URL, fileManager: FileManager = .default) {
        self.workspaceRootURL = workspaceRootURL
        self.fileManager = fileManager
    }

    func updateWorkspaceRootURL(_ url: URL) {
        workspaceRootURL = url
    }

    func list(projectID: String) throws -> [WorkflowDefinition] {
        let directory = try ensureProjectDirectory(projectID: projectID)
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map(readDefinition(at:))
    }

    func get(projectID: String, workflowID: String) throws -> WorkflowDefinition {
        let url = try definitionURL(projectID: projectID, workflowID: workflowID)
        guard fileManager.fileExists(atPath: url.path) else {
            throw StoreError.notFound
        }
        return try readDefinition(at: url)
    }

    func create(projectID: String, request: WorkflowDefinitionUpsertRequest) throws -> WorkflowDefinition {
        let now = Date.workflowDefinitionTimestamp()
        let definition = WorkflowDefinition(
            id: "wf_\(UUID().uuidString.lowercased())",
            projectId: try normalizedPathComponent(projectID),
            name: try sanitizedName(request.name),
            version: 1,
            lanes: request.lanes,
            nodes: request.nodes,
            edges: request.edges,
            enabled: request.enabled,
            createdAt: now,
            updatedAt: now
        )
        try validate(definition)
        try write(definition)
        return definition
    }

    func update(projectID: String, workflowID: String, request: WorkflowDefinitionUpsertRequest) throws -> WorkflowDefinition {
        let existing = try get(projectID: projectID, workflowID: workflowID)
        let next = WorkflowDefinition(
            id: existing.id,
            projectId: existing.projectId,
            name: try sanitizedName(request.name),
            version: existing.version + 1,
            lanes: request.lanes,
            nodes: request.nodes,
            edges: request.edges,
            enabled: request.enabled,
            createdAt: existing.createdAt,
            updatedAt: Date.workflowDefinitionTimestamp()
        )
        try validate(next)
        try write(next)
        return next
    }

    func delete(projectID: String, workflowID: String) throws {
        let url = try definitionURL(projectID: projectID, workflowID: workflowID)
        guard fileManager.fileExists(atPath: url.path) else {
            throw StoreError.notFound
        }
        try fileManager.removeItem(at: url)
    }

    func validate(_ definition: WorkflowDefinition) throws {
        _ = try normalizedPathComponent(definition.id)
        _ = try normalizedPathComponent(definition.projectId)
        _ = try sanitizedName(definition.name)

        let laneIDs = Set(definition.lanes.map(\.id))
        let nodeIDs = Set(definition.nodes.map(\.id))
        let edgeIDs = Set(definition.edges.map(\.id))

        guard laneIDs.count == definition.lanes.count,
              nodeIDs.count == definition.nodes.count,
              edgeIDs.count == definition.edges.count
        else {
            throw StoreError.invalidPayload
        }

        for lane in definition.lanes {
            _ = try normalizedIdentifier(lane.id)
            guard !lane.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw StoreError.invalidPayload
            }
        }

        for node in definition.nodes {
            _ = try normalizedIdentifier(node.id)
            guard laneIDs.contains(node.laneId),
                  !node.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  node.positionX.isFinite,
                  node.positionY.isFinite
            else {
                throw StoreError.invalidPayload
            }
        }

        for edge in definition.edges {
            _ = try normalizedIdentifier(edge.id)
            guard nodeIDs.contains(edge.sourceNodeId),
                  nodeIDs.contains(edge.targetNodeId),
                  edge.sourceNodeId != edge.targetNodeId
            else {
                throw StoreError.invalidPayload
            }
        }
    }

    private func readDefinition(at url: URL) throws -> WorkflowDefinition {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder.workflowDefinition.decode(WorkflowDefinition.self, from: data)
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.storageFailure
        }
    }

    private func write(_ definition: WorkflowDefinition) throws {
        do {
            let url = try definitionURL(projectID: definition.projectId, workflowID: definition.id)
            let data = try JSONEncoder.workflowDefinition.encode(definition)
            try data.write(to: url, options: .atomic)
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.storageFailure
        }
    }

    private func definitionURL(projectID: String, workflowID: String) throws -> URL {
        let directory = try ensureProjectDirectory(projectID: projectID)
        let workflowID = try normalizedPathComponent(workflowID)
        return directory.appendingPathComponent(workflowID).appendingPathExtension("json")
    }

    private func ensureProjectDirectory(projectID: String) throws -> URL {
        let projectID = try normalizedPathComponent(projectID)
        let directory = workspaceRootURL
            .appendingPathComponent("workflows")
            .appendingPathComponent(projectID)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            throw StoreError.storageFailure
        }
    }

    private func normalizedPathComponent(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              !normalized.contains("/"),
              !normalized.contains("\\"),
              normalized != ".",
              normalized != ".."
        else {
            throw StoreError.invalidPayload
        }
        return normalized
    }

    private func normalizedIdentifier(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw StoreError.invalidPayload
        }
        return normalized
    }

    private func sanitizedName(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw StoreError.invalidPayload
        }
        return normalized
    }
}

private extension JSONEncoder {
    static var workflowDefinition: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var workflowDefinition: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension Date {
    static func workflowDefinitionTimestamp() -> Date {
        Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    }
}
