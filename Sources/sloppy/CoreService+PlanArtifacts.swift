import Foundation
import Protocols

extension CoreService {
    func recordPlanArtifact(
        agentID: String,
        sessionID: String,
        sessionTitle: String,
        projectID: String?,
        messageEventID: String,
        markdown: String,
        createdAt: Date
    ) async throws -> AgentPlanArtifactEvent {
        guard let normalizedProjectID = normalizedProjectID(projectID ?? "") else {
            throw ProjectError.invalidProjectID
        }
        guard let project = await store.project(id: normalizedProjectID) else {
            throw ProjectError.notFound
        }
        let service = PlanArtifactService()
        let record = try service.createArtifact(
            PlanArtifactRequest(
                project: project,
                agentID: agentID,
                sessionID: sessionID,
                sessionTitle: sessionTitle,
                messageEventID: messageEventID,
                markdown: markdown,
                createdAt: createdAt,
                repositoryRootURL: repositoryRootForPlanArtifact(project: project),
                workspaceProjectURL: projectDirectoryURL(projectID: normalizedProjectID)
            )
        )
        return AgentPlanArtifactEvent(artifact: record)
    }

    public func getPlanArtifact(projectID: String, planName: String) async throws -> PlanArtifactRecord {
        guard let normalizedProjectID = normalizedProjectID(projectID),
              PlanArtifactService.isSafePlanName(planName)
        else {
            throw ProjectError.invalidProjectID
        }
        guard let project = await store.project(id: normalizedProjectID) else {
            throw ProjectError.notFound
        }
        let service = PlanArtifactService()
        guard let record = service.loadArtifact(
            projectID: normalizedProjectID,
            planName: planName,
            repositoryRootURL: repositoryRootForPlanArtifact(project: project),
            workspaceProjectURL: projectDirectoryURL(projectID: normalizedProjectID)
        ) else {
            throw ProjectError.notFound
        }
        return record
    }

    public func getPlanArtifactWebFile(projectID: String, planName: String, resourcePath: String?) async throws -> (data: Data, contentType: String) {
        guard let normalizedProjectID = normalizedProjectID(projectID),
              PlanArtifactService.isSafePlanName(planName)
        else {
            throw ProjectError.invalidProjectID
        }
        guard let project = await store.project(id: normalizedProjectID) else {
            throw ProjectError.notFound
        }
        let service = PlanArtifactService()
        guard let file = try service.webFile(
            projectID: normalizedProjectID,
            planName: planName,
            resourcePath: resourcePath,
            repositoryRootURL: repositoryRootForPlanArtifact(project: project),
            workspaceProjectURL: projectDirectoryURL(projectID: normalizedProjectID)
        ) else {
            throw ProjectError.notFound
        }
        return file
    }

    func fallbackPlanArtifactDirectoryURL(projectID: String) -> URL {
        projectDirectoryURL(projectID: projectID).appendingPathComponent("plans", isDirectory: true)
    }

    func fallbackPlanArtifactIndexRoots(projectID: String, rootURL: URL) -> [URL] {
        let plansURL = fallbackPlanArtifactDirectoryURL(projectID: projectID).standardizedFileURL
        let rootPath = rootURL.standardizedFileURL.path
        guard plansURL.path != rootPath,
              !plansURL.path.hasPrefix(rootPath + "/")
        else {
            return []
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: plansURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return []
        }
        return [plansURL]
    }

    private func repositoryRootForPlanArtifact(project: ProjectRecord) -> URL? {
        guard let raw = project.repoPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              !raw.hasPrefix("/projects/"),
              !raw.hasPrefix("projects/")
        else {
            return nil
        }
        let url = URL(fileURLWithPath: raw, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return nil
        }
        return url
    }
}
