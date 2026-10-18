import Foundation
import Observation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

@Observable
@MainActor
final class WorkspaceReferencePreviewModel {
    let reference: ChatComposerReference
    let apiClient: SloppyAPIClient
    private(set) var title: String
    private(set) var detail: String
    private(set) var document: String?
    private(set) var sourcePath: String?
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private var didLoad = false

    init(reference: ChatComposerReference, apiClient: SloppyAPIClient) {
        self.reference = reference
        self.apiClient = apiClient
        title = reference.title
        detail = reference.detail
    }

    func load() async {
        guard !didLoad, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            switch reference.target {
            case .skill(let agent, let id):
                let response = try await apiClient.fetchAgentSkills(agentId: agent)
                guard let skill = response.skills.first(where: { $0.id == id }) else {
                    errorMessage = "This skill is no longer installed for this agent."
                    return
                }
                title = skill.name
                detail = skill.description ?? reference.detail
                let root = URL(fileURLWithPath: response.skillsPath).standardizedFileURL.path + "/"
                let directory = URL(fileURLWithPath: skill.localPath).standardizedFileURL.path
                guard !response.skillsPath.isEmpty, directory.hasPrefix(root) else {
                    errorMessage = "This server does not expose the skill’s source through its agent files."
                    return
                }
                let path = "skills/" + directory.dropFirst(root.count) + "/SKILL.md"
                sourcePath = path
                document = try await apiClient.fetchAgentFileContent(agentId: agent, path: path).content
            case .command(let agent, let name):
                let response = try await apiClient.fetchChatSlashCommands(agentId: agent)
                guard let command = response.commands.first(where: { $0.name == name && $0.source != "skill" }) else {
                    errorMessage = "This command is no longer available for this agent."
                    return
                }
                title = "/" + command.name
                detail = command.description
                if let argument = command.argument { document = "/\(command.name) \(argument)" }
            case .task(let projectID, let taskID):
                let project = try await apiClient.fetchProject(id: projectID)
                guard let task = project.tasks?.first(where: { $0.id == taskID }) else {
                    errorMessage = "This task is no longer available in the project."
                    return
                }
                title = task.title
                detail = project.name
                document = "Status: \(task.status)\nTask: \(task.id)"
            case .file, .session, .website: break
            }
            didLoad = true
        } catch {
            errorMessage = "Could not load this reference from its server."
        }
    }
}

struct WorkspaceReferencePreview: View {
    let viewModel: WorkspaceReferencePreviewModel
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(viewModel.title, systemImage: viewModel.reference.systemImage)
                    .font(.title2.weight(.semibold))
                if !viewModel.detail.isEmpty { Text(viewModel.detail).textSelection(.enabled) }
                if let path = viewModel.sourcePath {
                    Text(path).font(.caption).foregroundStyle(theme.colors.textMuted).textSelection(.enabled)
                }
                if let document = viewModel.document {
                    Divider()
                    Text(verbatim: document).font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                if viewModel.isLoading { ProgressView() }
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(theme.colors.textSecondary)
                    Button("Retry") { Task { await viewModel.load() } }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(theme.colors.textPrimary)
        .background(theme.colors.background)
        .task { await viewModel.load() }
        .accessibilityIdentifier("workspace.reference-preview")
    }
}
