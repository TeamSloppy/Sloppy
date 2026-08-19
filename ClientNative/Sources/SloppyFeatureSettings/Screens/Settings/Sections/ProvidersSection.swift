import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

struct ProvidersSection: View {
    let config: SloppyConfig
    let apiClient: SloppyAPIClient?
    let onSave: (SloppyConfig) -> Void

    @State private var draft: [SloppyConfig.ModelConfig]
    @State private var selectedIndex: Int = 0
    @State private var modelOptions: [ChatModelOption] = []
    @State private var modelCatalogStatus: String?
    @State private var isLoadingModels = false
    @State private var modelCatalogLoadID: UUID?
    @Environment(\.theme) private var theme

    init(
        config: SloppyConfig,
        apiClient: SloppyAPIClient? = nil,
        onSave: @escaping (SloppyConfig) -> Void
    ) {
        self.config = config
        self.apiClient = apiClient
        self.onSave = onSave
        self._draft = State(initialValue: config.models)
    }

    private var hasChanges: Bool {
        guard draft.count == config.models.count else { return true }
        for (index, model) in draft.enumerated() {
            let original = config.models[index]
            if model.title != original.title || model.apiKey != original.apiKey || model.apiUrl != original.apiUrl || model.model != original.model {
                return true
            }
        }
        return false
    }

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.m) {
            SectionHeader("Providers", accentColor: c.accentCyan)

            if draft.isEmpty {
                Text("No providers configured.")
                    .font(.system(size: ty.body))
                    .foregroundColor(c.textMuted)
            } else {
                providerList
                if selectedIndex < draft.count {
                    providerEditor(index: selectedIndex)
                }
            }

            HStack(spacing: sp.s) {
                Button("+ ADD") { addProvider() }
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.accent)
                Spacer()
                if selectedIndex < draft.count && draft.count > 1 {
                    Button("REMOVE") { removeSelected() }
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.statusBlocked)
                }
            }

            SettingsSaveBar(
                hasChanges: hasChanges,
                statusText: hasChanges ? "Unsaved changes" : "Saved",
                onSave: { save() },
                onCancel: { resetDraft() }
            )
        }
        .task(id: modelCatalogRequest) {
            await loadProviderModels(debounce: true)
        }
    }

    private var providerList: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(draft.enumerated()), id: \.offset) { index, model in
                Button(action: { selectedIndex = index }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.title)
                                .font(.system(size: ty.body))
                                .foregroundColor(index == selectedIndex ? c.textPrimary : c.textSecondary)
                            Text(model.model)
                                .font(.system(size: ty.micro))
                                .foregroundColor(c.textMuted)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, sp.m)
                    .padding(.vertical, sp.s)
                    .background(index == selectedIndex ? c.surfaceRaised : Color.clear)
                    .border(c.border, lineWidth: bo.thin)
                }
            }
        }
        .background(c.surface)
        .border(c.border, lineWidth: bo.thin)
    }

    private func providerEditor(index: Int) -> some View {
        SettingsSectionCard("Edit Provider") {
            VStack(alignment: .leading, spacing: 0) {
                SettingsFieldRow("Title", text: Binding(
                    get: { draft[index].title },
                    set: { draft[index].title = $0 }
                ))
                SettingsDivider()
                SettingsFieldRow("API URL", text: Binding(
                    get: { draft[index].apiUrl },
                    set: { draft[index].apiUrl = $0 }
                ))
                SettingsDivider()
                SettingsFieldRow("API Key", text: Binding(
                    get: { draft[index].apiKey },
                    set: { draft[index].apiKey = $0 }
                ), isSecure: true)
                SettingsDivider()
                SettingsModelPickerRow(
                    modelID: Binding(
                        get: { draft[index].model },
                        set: { draft[index].model = $0 }
                    ),
                    models: modelOptions,
                    providerTitle: draft[index].title,
                    status: modelCatalogStatus,
                    isLoading: isLoadingModels,
                    onRefresh: {
                        Task { await loadProviderModels(debounce: false) }
                    }
                )
            }
        }
    }

    private func addProvider() {
        draft.append(SloppyConfig.ModelConfig(title: "new-provider", apiKey: "", apiUrl: "", model: ""))
        selectedIndex = draft.count - 1
    }

    private func removeSelected() {
        guard draft.count > 1 else { return }
        draft.remove(at: selectedIndex)
        selectedIndex = max(0, selectedIndex - 1)
    }

    private func resetDraft() {
        draft = config.models
        selectedIndex = min(selectedIndex, max(0, draft.count - 1))
    }

    private func save() {
        var updated = config
        updated.models = draft
        onSave(updated)
    }

    private var modelCatalogRequest: ModelCatalogRequest? {
        guard selectedIndex < draft.count,
              let providerId = providerID(for: draft[selectedIndex]),
              Self.catalogProviderIDs.contains(providerId)
        else {
            return nil
        }

        let model = draft[selectedIndex]
        return ModelCatalogRequest(
            providerId: providerId,
            apiKey: model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            apiUrl: model.apiUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    @MainActor
    private func loadProviderModels(debounce: Bool) async {
        guard let apiClient else {
            modelCatalogLoadID = nil
            isLoadingModels = false
            modelOptions = []
            modelCatalogStatus = "Connect to a server to load its model catalog."
            return
        }
        guard let request = modelCatalogRequest else {
            modelCatalogLoadID = nil
            isLoadingModels = false
            modelOptions = []
            modelCatalogStatus = "This custom provider does not expose a searchable catalog."
            return
        }

        if debounce {
            do {
                try await Task.sleep(for: .milliseconds(350))
                try Task.checkCancellation()
            } catch {
                return
            }
        }

        let loadID = UUID()
        modelCatalogLoadID = loadID
        isLoadingModels = true
        modelCatalogStatus = "Loading models…"
        defer {
            if modelCatalogLoadID == loadID {
                isLoadingModels = false
            }
        }

        do {
            let models = try await apiClient.fetchProviderModels(
                providerId: request.providerId,
                apiKey: request.apiKey.nilIfEmpty,
                apiUrl: request.apiUrl.nilIfEmpty
            )
            try Task.checkCancellation()
            guard modelCatalogLoadID == loadID else { return }
            modelOptions = models.uniquedByID().sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            modelCatalogStatus = modelOptions.isEmpty
                ? "No models returned. You can still use a custom model ID."
                : nil
        } catch is CancellationError {
            return
        } catch {
            guard modelCatalogLoadID == loadID else { return }
            modelOptions = []
            modelCatalogStatus = "Couldn’t load models. You can still use a custom model ID."
        }
    }

    private func providerID(for model: SloppyConfig.ModelConfig) -> String? {
        if let catalogId = model.providerCatalogId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !catalogId.isEmpty {
            return catalogId
        }

        let modelID = model.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if let prefix = modelID.split(separator: ":", maxSplits: 1).first.map(String.init),
           Self.catalogProviderIDs.contains(prefix) {
            return prefix == "anthropic-oauth" ? "anthropic-oauth" : prefix
        }

        let title = model.title.lowercased()
        let apiUrl = model.apiUrl.lowercased()
        if (title.contains("oauth") || title.contains("deeplink")) && !title.contains("anthropic") {
            return "openai-oauth"
        }
        if apiUrl.contains("chatgpt.com") { return "openai-oauth" }
        if title.contains("openai") || apiUrl.contains("openai") { return "openai-api" }
        if title.contains("openrouter") || apiUrl.contains("openrouter") { return "openrouter" }
        if apiUrl.contains(":1234") { return "openai-api" }
        if title.contains("ollama") || apiUrl.contains("ollama") || apiUrl.contains("11434") { return "ollama" }
        if title.contains("gemini") || apiUrl.contains("generativelanguage.googleapis.com") { return "gemini" }
        if title.contains("anthropic-oauth") { return "anthropic-oauth" }
        if title.contains("anthropic") || apiUrl.contains("anthropic") { return "anthropic" }
        return nil
    }

    private static let catalogProviderIDs: Set<String> = [
        "openai-api",
        "openai-oauth",
        "openrouter",
        "ollama",
        "gemini",
        "anthropic",
        "anthropic-oauth",
    ]
}

private struct ModelCatalogRequest: Hashable {
    let providerId: String
    let apiKey: String
    let apiUrl: String
}

private struct SettingsModelPickerRow: View {
    @Binding var modelID: String

    let models: [ChatModelOption]
    let providerTitle: String
    let status: String?
    let isLoading: Bool
    let onRefresh: () -> Void

    @State private var isPresented = false
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text("Model")
                .font(.system(size: theme.typography.caption, weight: .medium))
                .foregroundColor(theme.colors.textSecondary)

            Button {
                isPresented = true
            } label: {
                HStack(spacing: theme.spacing.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedModelTitle)
                            .font(.system(size: theme.typography.body, weight: .medium))
                            .foregroundColor(theme.colors.textPrimary)
                            .lineLimit(1)

                        if let selectedModelSubtitle {
                            Text(selectedModelSubtitle)
                                .font(.system(size: theme.typography.micro))
                                .foregroundColor(theme.colors.textMuted)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: theme.spacing.s)

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(theme.colors.textSecondary)
                    }

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: theme.typography.micro, weight: .semibold))
                        .foregroundColor(theme.colors.textMuted)
                }
                .padding(.horizontal, theme.spacing.s)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(
                    theme.colors.surfaceRaised.opacity(0.72 as CGFloat),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(theme.colors.border, lineWidth: theme.borders.thin)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                pickerContent
                    .presentationCompactAdaptation(.popover)
            }
            .accessibilityLabel("Model \(selectedModelTitle)")
            .accessibilityHint("Opens searchable model catalog")
            .accessibilityIdentifier("settings.providers.model-picker")

            Text("Search the provider catalog or enter an exact custom model ID.")
                .font(.system(size: theme.typography.micro))
                .foregroundColor(theme.colors.textMuted)
        }
        .padding(.horizontal, theme.spacing.m)
        .padding(.vertical, theme.spacing.s)
    }

    private var selectedModel: ChatModelOption? {
        models.first { $0.id == modelID }
    }

    private var selectedModelTitle: String {
        if modelID.isEmpty {
            return "Choose a model"
        }
        return selectedModel?.title ?? modelID
    }

    private var selectedModelSubtitle: String? {
        guard !modelID.isEmpty else { return "No model selected" }
        if let selectedModel, selectedModel.title != selectedModel.id {
            return selectedModel.id
        }
        return selectedModel == nil ? "Custom model ID" : nil
    }

    private var filteredModels: [ChatModelOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return models }
        return models.filter {
            $0.title.localizedStandardContains(query) || $0.id.localizedStandardContains(query)
        }
    }

    private var customModelID: String? {
        let candidate = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty,
              !models.contains(where: { $0.id.caseInsensitiveCompare(candidate) == .orderedSame })
        else {
            return nil
        }
        return candidate
    }

    private var pickerContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: theme.spacing.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(theme.colors.textMuted)
                TextField("Search models", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
            }
            .padding(.horizontal, theme.spacing.m)
            .frame(height: 42)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: theme.spacing.xs) {
                    Text(providerTitle.isEmpty ? "MODELS" : providerTitle.uppercased())
                        .font(.system(size: theme.typography.caption, weight: .semibold))
                        .foregroundColor(theme.colors.textMuted)
                        .padding(.horizontal, theme.spacing.m)
                        .padding(.top, theme.spacing.s)

                    if filteredModels.isEmpty && customModelID == nil {
                        Text(isLoading ? "Loading models…" : "No matching models")
                            .font(.system(size: theme.typography.caption))
                            .foregroundColor(theme.colors.textMuted)
                            .frame(maxWidth: .infinity, minHeight: 90)
                    } else {
                        ForEach(filteredModels) { model in
                            modelRow(model)
                        }

                        if let customModelID {
                            customModelRow(customModelID)
                        }
                    }
                }
                .padding(.vertical, theme.spacing.s)
            }
            .frame(maxHeight: 340)

            Divider()

            HStack(spacing: theme.spacing.s) {
                if let status {
                    Text(status)
                        .font(.system(size: theme.typography.micro))
                        .foregroundColor(theme.colors.textMuted)
                        .lineLimit(2)
                }

                Spacer(minLength: theme.spacing.s)

                Button {
                    onRefresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundColor(theme.colors.textSecondary)
                .disabled(isLoading)
            }
            .padding(theme.spacing.m)
        }
        .frame(width: 380)
        .onAppear {
            searchText = ""
            isSearchFocused = true
        }
    }

    private func modelRow(_ model: ChatModelOption) -> some View {
        Button {
            modelID = model.id
            isPresented = false
        } label: {
            HStack(spacing: theme.spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: theme.spacing.xs) {
                        Text(model.title)
                            .foregroundColor(theme.colors.textPrimary)
                            .lineLimit(1)
                        if let contextWindow = model.contextWindow {
                            Text(contextWindow)
                                .font(.system(size: theme.typography.micro))
                                .foregroundColor(theme.colors.textMuted)
                        }
                    }
                    if model.title != model.id {
                        Text(model.id)
                            .font(.system(size: theme.typography.micro))
                            .foregroundColor(theme.colors.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: theme.spacing.s)

                if modelID == model.id {
                    Image(systemName: "checkmark")
                        .foregroundColor(theme.colors.accent)
                }
            }
            .padding(.horizontal, theme.spacing.m)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                modelID == model.id
                    ? theme.colors.accent.opacity(0.14 as CGFloat)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
    }

    private func customModelRow(_ customModelID: String) -> some View {
        Button {
            modelID = customModelID
            isPresented = false
        } label: {
            HStack(spacing: theme.spacing.s) {
                Image(systemName: "plus.circle")
                    .foregroundColor(theme.colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use “\(customModelID)”")
                        .foregroundColor(theme.colors.textPrimary)
                        .lineLimit(1)
                    Text("Custom model ID")
                        .font(.system(size: theme.typography.micro))
                        .foregroundColor(theme.colors.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, theme.spacing.m)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension Array where Element == ChatModelOption {
    func uniquedByID() -> [ChatModelOption] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}
