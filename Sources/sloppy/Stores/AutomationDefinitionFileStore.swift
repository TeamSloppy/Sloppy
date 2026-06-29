import Foundation
import Protocols

final class AutomationDefinitionFileStore {
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

    func list(projectID: String) throws -> [AutomationDefinition] {
        let directory = try ensureProjectDirectory(projectID: projectID)
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map(readDefinition(at:))
    }

    func get(projectID: String, automationID: String) throws -> AutomationDefinition {
        let url = try definitionURL(projectID: projectID, automationID: automationID)
        guard fileManager.fileExists(atPath: url.path) else {
            throw StoreError.notFound
        }
        return try readDefinition(at: url)
    }

    func create(projectID: String, request: AutomationDefinitionUpsertRequest) throws -> AutomationDefinition {
        let now = Date.automationDefinitionTimestamp()
        let definition = AutomationDefinition(
            id: "auto_\(UUID().uuidString.lowercased())",
            projectId: try normalizedPathComponent(projectID),
            name: try sanitizedName(request.name),
            description: sanitizedDescription(request.description),
            version: 1,
            enabled: request.enabled,
            workflowId: try normalizedPathComponent(request.workflowId),
            repositoryFullName: try normalizedRepository(request.repositoryFullName),
            trigger: request.trigger,
            taskMode: request.taskMode,
            model: sanitizedOptionalValue(request.model),
            permissionsScope: request.permissionsScope,
            createdAt: now,
            updatedAt: now
        )
        try validate(definition)
        try write(definition)
        return definition
    }

    func update(projectID: String, automationID: String, request: AutomationDefinitionUpsertRequest) throws -> AutomationDefinition {
        let existing = try get(projectID: projectID, automationID: automationID)
        let next = AutomationDefinition(
            id: existing.id,
            projectId: existing.projectId,
            name: try sanitizedName(request.name),
            description: sanitizedDescription(request.description),
            version: existing.version + 1,
            enabled: request.enabled,
            workflowId: try normalizedPathComponent(request.workflowId),
            repositoryFullName: try normalizedRepository(request.repositoryFullName),
            trigger: request.trigger,
            taskMode: request.taskMode,
            model: sanitizedOptionalValue(request.model),
            permissionsScope: request.permissionsScope,
            createdAt: existing.createdAt,
            updatedAt: Date.automationDefinitionTimestamp()
        )
        try validate(next)
        try write(next)
        return next
    }

    func delete(projectID: String, automationID: String) throws {
        let url = try definitionURL(projectID: projectID, automationID: automationID)
        guard fileManager.fileExists(atPath: url.path) else {
            throw StoreError.notFound
        }
        try fileManager.removeItem(at: url)
    }

    func validate(_ definition: AutomationDefinition) throws {
        _ = try normalizedPathComponent(definition.id)
        _ = try normalizedPathComponent(definition.projectId)
        _ = try normalizedPathComponent(definition.workflowId)
        _ = try sanitizedName(definition.name)
        _ = try normalizedRepository(definition.repositoryFullName)

        guard definition.version > 0 else {
            throw StoreError.invalidPayload
        }

        if let description = definition.description,
           description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw StoreError.invalidPayload
        }

        if let model = definition.model,
           model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw StoreError.invalidPayload
        }

        try validateTrigger(definition.trigger)
    }

    private func validateTrigger(_ trigger: AutomationTrigger) throws {
        switch trigger.type {
        case .manual:
            return
        case .cron:
            guard let schedule = trigger.config["schedule"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !schedule.isEmpty
            else {
                throw StoreError.invalidPayload
            }
        case .webhook:
            guard let secretId = trigger.config["secretId"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !secretId.isEmpty
            else {
                throw StoreError.invalidPayload
            }
        case .githubPullRequest, .githubPullRequestReview:
            if let actions = trigger.config["actions"]?.asArray {
                guard actions.allSatisfy({ ($0.asString?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) }) else {
                    throw StoreError.invalidPayload
                }
            }
            if let reviewStates = trigger.config["reviewStates"]?.asArray {
                guard reviewStates.allSatisfy({ ($0.asString?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) }) else {
                    throw StoreError.invalidPayload
                }
            }
            if let branchPatterns = trigger.config["branchPatterns"]?.asArray {
                guard branchPatterns.allSatisfy({ ($0.asString?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) }) else {
                    throw StoreError.invalidPayload
                }
            }
        }
    }

    private func readDefinition(at url: URL) throws -> AutomationDefinition {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder.automationDefinition.decode(AutomationDefinition.self, from: data)
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.storageFailure
        }
    }

    private func write(_ definition: AutomationDefinition) throws {
        do {
            let url = try definitionURL(projectID: definition.projectId, automationID: definition.id)
            let data = try JSONEncoder.automationDefinition.encode(definition)
            try data.write(to: url, options: .atomic)
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.storageFailure
        }
    }

    private func definitionURL(projectID: String, automationID: String) throws -> URL {
        let directory = try ensureProjectDirectory(projectID: projectID)
        let automationID = try normalizedPathComponent(automationID)
        return directory.appendingPathComponent(automationID).appendingPathExtension("json")
    }

    private func ensureProjectDirectory(projectID: String) throws -> URL {
        let projectID = try normalizedPathComponent(projectID)
        let directory = workspaceRootURL
            .appendingPathComponent("automations")
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

    private func sanitizedName(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw StoreError.invalidPayload
        }
        return normalized
    }

    private func normalizedRepository(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              !normalized.hasPrefix("/"),
              normalized.split(separator: "/").count == 2,
              !normalized.contains(" ")
        else {
            throw StoreError.invalidPayload
        }
        return normalized
    }

    private func sanitizedDescription(_ value: String?) -> String? {
        sanitizedOptionalValue(value)
    }

    private func sanitizedOptionalValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

private extension JSONEncoder {
    static var automationDefinition: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var automationDefinition: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension Date {
    static func automationDefinitionTimestamp() -> Date {
        let formatter = ISO8601DateFormatter()
        let string = formatter.string(from: Date())
        return formatter.date(from: string) ?? Date()
    }
}
