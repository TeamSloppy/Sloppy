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


public struct ChatComposerTabActions {
    public let tabProgress: @MainActor (CGFloat) -> Void
    public let showOverview: @MainActor () -> Void
    public let beginOverviewGesture: @MainActor () -> Void
    public let updateOverviewGesture: @MainActor (CGFloat) -> Void
    public let endOverviewGesture: @MainActor (CGFloat, CGFloat) -> Void
    public let createTab: @MainActor () -> Void
    public let selectAdjacentTab: @MainActor (Int) -> Void

    public init(
        tabProgress: @escaping @MainActor (CGFloat) -> Void,
        showOverview: @escaping @MainActor () -> Void,
        beginOverviewGesture: @escaping @MainActor () -> Void = {},
        updateOverviewGesture: @escaping @MainActor (CGFloat) -> Void = { _ in },
        endOverviewGesture: @escaping @MainActor (CGFloat, CGFloat) -> Void = { _, _ in },
        createTab: @escaping @MainActor () -> Void,
        selectAdjacentTab: @escaping @MainActor (Int) -> Void = { _ in }
    ) {
        self.tabProgress = tabProgress
        self.showOverview = showOverview
        self.beginOverviewGesture = beginOverviewGesture
        self.updateOverviewGesture = updateOverviewGesture
        self.endOverviewGesture = endOverviewGesture
        self.createTab = createTab
        self.selectAdjacentTab = selectAdjacentTab
    }
}

public struct ChatAgentToolbarMenu: View {
    public let selectedAgent: APIAgentRecord?
    public let agents: [APIAgentRecord]
    public let onSelectAgent: (APIAgentRecord) -> Void

    @Environment(\.theme) private var theme

    public init(
        selectedAgent: APIAgentRecord?,
        agents: [APIAgentRecord],
        onSelectAgent: @escaping (APIAgentRecord) -> Void
    ) {
        self.selectedAgent = selectedAgent
        self.agents = agents
        self.onSelectAgent = onSelectAgent
    }

    public var body: some View {
        Menu {
            Section("Agent") {
                if agents.isEmpty {
                    ComposerMenuItem(title: "No agents", isSelected: false)
                } else {
                    ForEach(agents) { agent in
                        Button {
                            onSelectAgent(agent)
                        } label: {
                            ComposerMenuItem(
                                title: agent.displayName,
                                isSelected: selectedAgent?.id == agent.id
                            )
                        }
                    }
                }
            }
        } label: {
            Label {
                Text(selectedAgent?.displayName ?? "Agent")
            } icon: {
                AgentBotAvatar(agentID: selectedAgent?.id ?? "sloppy", size: 22, paletteID: selectedAgent?.pet?.visual?.paletteId)
            }
                .disabled(agents.isEmpty)
                .labelStyle(.titleOnly)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }
}

#Preview {
    ChatAgentToolbarMenu(
        selectedAgent: .init(
            id: "",
            displayName: "Anton"
        ),
        agents: [],
        onSelectAgent: { _ in }
    )
}

public struct ChatModelToolbarMenu: View {
    public let selectedModelId: String
    public let models: [ChatModelOption]
    public let onSelectModel: (ChatModelOption) -> Void

    public init(
        selectedModelId: String,
        models: [ChatModelOption],
        onSelectModel: @escaping (ChatModelOption) -> Void
    ) {
        self.selectedModelId = selectedModelId
        self.models = models
        self.onSelectModel = onSelectModel
    }

    public var body: some View {
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
        } label: {
            Label(selectedModelTitle, systemImage: "brain")
                .disabled(models.isEmpty)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var selectedModelTitle: String {
        guard let selected = models.first(where: { $0.id == selectedModelId }) else {
            return selectedModelId.isEmpty ? "Model" : selectedModelId
        }
        return selected.title
    }
}

public struct ChatContextToolbarMenu: View {
    public let selectedAgent: APIAgentRecord?
    public let agents: [APIAgentRecord]
    public let selectedModelId: String
    public let models: [ChatModelOption]
    public let onSelectAgent: (APIAgentRecord) -> Void
    public let onSelectModel: (ChatModelOption) -> Void

    public init(
        selectedAgent: APIAgentRecord?,
        agents: [APIAgentRecord],
        selectedModelId: String,
        models: [ChatModelOption],
        onSelectAgent: @escaping (APIAgentRecord) -> Void,
        onSelectModel: @escaping (ChatModelOption) -> Void
    ) {
        self.selectedAgent = selectedAgent
        self.agents = agents
        self.selectedModelId = selectedModelId
        self.models = models
        self.onSelectAgent = onSelectAgent
        self.onSelectModel = onSelectModel
    }

    public var body: some View {
        Menu {
            Section("Agent") {
                if agents.isEmpty {
                    ComposerMenuItem(title: "No agents", isSelected: false)
                } else {
                    ForEach(agents) { agent in
                        Button {
                            onSelectAgent(agent)
                        } label: {
                            ComposerMenuItem(
                                title: agent.displayName,
                                isSelected: selectedAgent?.id == agent.id
                            )
                        }
                    }
                }
            }

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
        } label: {
            Label(selectedAgent?.displayName ?? "Agent", systemImage: "brain")
                .lineLimit(1)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help("Agent and model")
        .accessibilityLabel("Agent and model")
    }
}
