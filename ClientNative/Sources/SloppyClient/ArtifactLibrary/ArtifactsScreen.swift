import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI

@Observable
@MainActor
private final class ArtifactsViewModel {
    private let apiClient: SloppyAPIClient
    private let cacheStore: ClientCacheStore

    var artifacts: [ChatArtifactRecord] = []
    var isLoading = false
    var errorMessage: String?

    init(apiClient: SloppyAPIClient, cacheStore: ClientCacheStore) {
        self.apiClient = apiClient
        self.cacheStore = cacheStore
    }

    func load(sessions: [ChatSessionSummary]) async {
        guard !isLoading else { return }
        guard !sessions.isEmpty else {
            artifacts = []
            errorMessage = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        let apiClient = apiClient
        let cacheStore = cacheStore
        let details = await withTaskGroup(
            of: ChatSessionDetail?.self,
            returning: [ChatSessionDetail].self
        ) { group in
            for session in sessions {
                group.addTask {
                    let cached = await cacheStore.loadSessionDetail(
                        agentId: session.agentId,
                        sessionId: session.id
                    )
                    do {
                        let detail = try await apiClient.fetchAgentSession(
                            agentId: session.agentId,
                            sessionId: session.id
                        )
                        await cacheStore.cacheSessionDetail(agentId: session.agentId, detail: detail)
                        return detail
                    } catch {
                        return cached
                    }
                }
            }

            var loaded: [ChatSessionDetail] = []
            for await detail in group {
                if let detail {
                    loaded.append(detail)
                }
            }
            return loaded
        }

        artifacts = ChatArtifactCatalog.build(from: details)
        errorMessage = details.isEmpty ? "Не удалось загрузить артефакты" : nil
    }
}

@MainActor
struct ArtifactsScreen: View {
    let sessions: [ChatSessionSummary]
    let onOpenSession: @MainActor (ChatSessionSummary) -> Void

    @State private var viewModel: ArtifactsViewModel
    @State private var searchText = ""
    @Environment(\.theme) private var theme

    init(
        apiClient: SloppyAPIClient,
        cacheStore: ClientCacheStore,
        sessions: [ChatSessionSummary],
        onOpenSession: @escaping @MainActor (ChatSessionSummary) -> Void
    ) {
        self.sessions = sessions
        self.onOpenSession = onOpenSession
        _viewModel = State(
            initialValue: ArtifactsViewModel(apiClient: apiClient, cacheStore: cacheStore)
        )
    }

    private var catalogVersion: String {
        sessions.map { "\($0.id):\($0.updatedAt.timeIntervalSinceReferenceDate)" }
            .joined(separator: "|")
    }

    private var filteredArtifacts: [ChatArtifactRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.artifacts }
        return viewModel.artifacts.filter { artifact in
            artifact.name.localizedCaseInsensitiveContains(query)
                || artifact.session.title.localizedCaseInsensitiveContains(query)
                || artifact.mimeType.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .background(theme.colors.background)
        .searchable(text: $searchText, prompt: "Поиск артефактов")
        .task(id: catalogVersion) {
            await viewModel.load(sessions: sessions)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Артефакты")
                .font(.system(size: theme.typography.title, weight: .semibold))
                .foregroundColor(theme.colors.textPrimary)

            if !viewModel.artifacts.isEmpty {
                Text(viewModel.artifacts.count.formatted())
                    .font(.system(size: theme.typography.caption, weight: .medium))
                    .foregroundColor(theme.colors.textMuted)
            }

            Spacer()

            Button {
                Task { await viewModel.load(sessions: sessions) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            .help("Обновить")
            .accessibilityLabel("Обновить артефакты")
        }
        .padding(.horizontal, theme.spacing.l)
        .padding(.vertical, theme.spacing.m)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.artifacts.isEmpty {
            ProgressView("Загрузка артефактов…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage, viewModel.artifacts.isEmpty {
            ContentUnavailableView(
                "Артефакты недоступны",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if filteredArtifacts.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? "Артефактов пока нет" : "Ничего не найдено",
                systemImage: "doc.on.doc",
                description: Text(
                    searchText.isEmpty
                        ? "Файлы из чатов появятся здесь."
                        : "Попробуйте изменить запрос."
                )
            )
        } else {
            List(filteredArtifacts) { artifact in
                Button {
                    onOpenSession(artifact.session)
                } label: {
                    ArtifactRow(artifact: artifact)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .accessibilityHint("Открыть исходный чат")
            }
            .listStyle(.inset)
            .refreshable {
                await viewModel.load(sessions: sessions)
            }
        }
    }
}

@MainActor
private struct ArtifactRow: View {
    let artifact: ChatArtifactRecord

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: theme.typography.heading))
                .foregroundColor(theme.colors.accentCyan)
                .frame(width: 36, height: 36)
                .background(theme.colors.surfaceRaised, in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                Text(artifact.name)
                    .font(.system(size: theme.typography.body, weight: .medium))
                    .foregroundColor(theme.colors.textPrimary)
                    .lineLimit(1)

                Text(artifact.session.title)
                    .font(.system(size: theme.typography.caption))
                    .foregroundColor(theme.colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: theme.spacing.m)

            VStack(alignment: .trailing, spacing: theme.spacing.xs) {
                Text(artifact.createdAt, format: .dateTime.day().month(.abbreviated).year())
                Text(ByteCountFormatter.string(fromByteCount: Int64(artifact.sizeBytes), countStyle: .file))
            }
            .font(.system(size: theme.typography.caption))
            .foregroundColor(theme.colors.textMuted)
        }
        .contentShape(Rectangle())
        .padding(.vertical, theme.spacing.xs)
    }

    private var systemImage: String {
        if artifact.mimeType.hasPrefix("image/") {
            return "photo"
        }
        if artifact.mimeType.hasPrefix("audio/") {
            return "waveform"
        }
        if artifact.mimeType.hasPrefix("video/") {
            return "film"
        }
        if artifact.mimeType == "application/pdf" {
            return "doc.richtext"
        }
        return "doc"
    }
}
