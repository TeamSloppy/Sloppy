import Foundation
import Observation
import SwiftUI
import SloppyClientUI
import SloppyClientCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif


#if !os(macOS)
struct MobileComposerAgentPicker: View {
    let selectedAgent: APIAgentRecord?
    let agents: [APIAgentRecord]
    let selectedProjectID: String?
    let selectedProjectName: String?
    let projects: [APIProjectRecord]
    let onSelectAgent: (APIAgentRecord) -> Void
    let onSelectProject: (APIProjectRecord) -> Void
    let onSelectPersonal: () -> Void

    var body: some View {
        Menu {
            Section("Context") {
                Button(action: onSelectPersonal) {
                    ComposerMenuItem(title: "Personal", isSelected: selectedProjectID == nil)
                }
                ForEach(projects) { project in
                    Button { onSelectProject(project) } label: {
                        ComposerMenuItem(title: project.name, isSelected: selectedProjectID == project.id)
                    }
                }
            }
            Section("Agent") {
                ForEach(agents) { agent in
                    Button { onSelectAgent(agent) } label: {
                        ComposerMenuItem(title: agent.displayName, isSelected: selectedAgent?.id == agent.id)
                    }
                }
            }
        } label: {
            ComposerMenuChip(title: contextTitle, isEnabled: true)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Chat context \(contextTitle)")
        .accessibilityIdentifier("chat.composer.agent-picker")
    }

    private var contextTitle: String {
        guard let selectedProjectName else { return selectedAgent?.displayName ?? "Personal" }
        guard let selectedAgent, selectedAgent.displayName != selectedProjectName else { return selectedProjectName }
        return "\(selectedProjectName) \(selectedAgent.displayName)"
    }
}

struct MobileComposerServerPicker: View {
    let endpoint: SloppyInstanceEndpoint
    @Environment(\.chatComposerConnectionActions) private var actions
    @Environment(\.theme) private var theme

    var body: some View {
        Menu {
            ForEach(actions?.instances ?? []) { instance in
                Button { actions?.selectInstance(instance) } label: {
                    ComposerMenuItem(title: instance.displayName, isSelected: instance.endpoint == endpoint)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "cloud")
                ComposerMenuChip(title: serverTitle, isEnabled: !(actions?.instances.isEmpty ?? true))
            }
            .foregroundColor(theme.colors.textSecondary)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(actions?.instances.isEmpty ?? true)
        .accessibilityLabel("Server \(serverTitle)")
        .accessibilityIdentifier("chat.composer.server-picker")
    }

    private var serverTitle: String {
        actions?.instances.first(where: { $0.endpoint == endpoint })?.displayName
            ?? endpoint.coordinatorBaseURL.host ?? "Server"
    }
}

struct MobileComposerModelPicker: View {
    let selectedModelId: String
    let models: [ChatModelOption]
    let selectedEffort: ChatReasoningEffort
    let supportsReasoningEffort: Bool
    let onSelectModel: (ChatModelOption) -> Void
    let onSelectEffort: (ChatReasoningEffort) -> Void

    var body: some View {
        Menu {
            Section("Model") {
                if models.isEmpty {
                    ComposerMenuItem(title: "No models", isSelected: false)
                } else {
                    ForEach(models) { model in
                        Button {
                            onSelectModel(model)
                        } label: {
                            ComposerMenuItem(
                                title: model.title,
                                subtitle: model.id == model.title ? nil : model.id,
                                isSelected: selectedModelId == model.id
                            )
                        }
                    }
                }
            }

            if supportsReasoningEffort {
                Section("Reasoning") {
                    ForEach(ChatReasoningEffort.allCases) { effort in
                        Button {
                            onSelectEffort(effort)
                        } label: {
                            ComposerMenuItem(
                                title: effort.title,
                                isSelected: selectedEffort == effort
                            )
                        }
                    }
                }
            }
        } label: {
            ComposerMenuChip(title: selectedModelTitle, isEnabled: !models.isEmpty)
                .frame(maxWidth: 180, minHeight: ChatComposerView.phoneCircleSize, alignment: .leading)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(models.isEmpty)
        .accessibilityLabel("Model \(selectedModelTitle)")
        .accessibilityIdentifier("chat.composer.model-picker")
    }

    private var selectedModelTitle: String {
        guard let selected = models.first(where: { $0.id == selectedModelId }) else {
            return selectedModelId.isEmpty ? "Model" : selectedModelId
        }
        return selected.title
    }
}
#endif
