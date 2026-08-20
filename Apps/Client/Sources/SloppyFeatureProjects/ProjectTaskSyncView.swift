import AdaEngine
import Foundation
import SloppyClientCore
import SloppyClientUI

@MainActor
struct ProjectTaskSyncView: View {
    let projectId: String
    let apiClient: SloppyAPIClient

    @Environment(\.theme) private var theme
    @State private var sourceKind: APITaskSyncSourceKind = .query
    @State private var sourceValue = ""
    @State private var oauthToken = ""
    @State private var intervalMinutes = "5"
    @State private var inboundMappings = ""
    @State private var outboundMappings = ""
    @State private var health = "unknown"
    @State private var message = ""
    @State private var isBusy = false

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return ScrollView {
            VStack(alignment: .leading, spacing: sp.l) {
                VStack(alignment: .leading, spacing: sp.s) {
                    Text("YANDEX STARTTRACK")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.textPrimary)
                    HStack(spacing: sp.s) {
                        ForEach(APITaskSyncSourceKind.allCases, id: \.self) { kind in
                            Button(kind.rawValue.uppercased()) { sourceKind = kind }
                                .foregroundColor(sourceKind == kind ? c.accent : c.textMuted)
                        }
                    }
                    TextField(sourcePlaceholder, text: $sourceValue)
                    TextField("OAuth token", text: $oauthToken)
                    TextField("Polling interval in minutes", text: $intervalMinutes)
                }
                .padding(sp.m)
                .background(c.surface)
                .border(c.border, lineWidth: bo.thin)

                VStack(alignment: .leading, spacing: sp.s) {
                    Text("INBOUND STATUS MAPPINGS")
                        .font(.system(size: ty.micro))
                        .foregroundColor(c.textMuted)
                    TextEditor("startrek-status=sloppy_status", text: $inboundMappings)
                        .frame(height: 120)
                    Text("OUTBOUND STATUS MAPPINGS")
                        .font(.system(size: ty.micro))
                        .foregroundColor(c.textMuted)
                    TextEditor("sloppy_status=startrek-status", text: $outboundMappings)
                        .frame(height: 120)
                }
                .padding(sp.m)
                .background(c.surface)
                .border(c.border, lineWidth: bo.thin)

                HStack(spacing: sp.s) {
                    Button("SAVE TOKEN") { saveToken() }
                    Button("DISCOVER") { discover() }
                    Button("LINK / SAVE") { link() }
                    Button("SYNC NOW") { syncNow() }
                    Button("UNLINK") { unlink() }
                }
                .disabled(isBusy)
                .foregroundColor(c.accent)

                Text("Health: \(health)\(message.isEmpty ? "" : " — \(message)")")
                    .font(.system(size: ty.caption))
                    .foregroundColor(health == "conflict" || health == "error" ? c.statusBlocked : c.textMuted)
            }
            .padding(sp.l)
        }
        .onAppear { load() }
    }

    private var sourcePlaceholder: String {
        switch sourceKind {
        case .queue: "QUEUE or https://st.yandex-team.ru/QUEUE"
        case .query: "Assignee: me() Resolution: empty()"
        case .savedFilter: "filter:12345"
        }
    }

    private var source: APIProjectTaskSyncSource {
        APIProjectTaskSyncSource(kind: sourceKind, value: sourceValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func mappings(_ text: String) -> [String: String] {
        text.split(whereSeparator: \Character.isNewline).reduce(into: [:]) { result, line in
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
                result[parts[0].lowercased()] = parts[1]
            }
        }
    }

    private func mappingText(_ values: [String: String]) -> String {
        values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
    }

    private func load() {
        perform {
            let settings = try await apiClient.fetchTaskSyncSettings(projectId: projectId)
            sourceKind = settings.source?.kind ?? .query
            sourceValue = settings.source?.value ?? ""
            intervalMinutes = String(settings.syncSchedule.intervalMinutes)
            inboundMappings = mappingText(settings.inboundStatusMappings)
            outboundMappings = mappingText(settings.statusMappings)
            health = settings.health.status
            message = settings.health.message ?? ""
        }
    }

    private func saveToken() {
        let token = oauthToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        perform {
            _ = try await apiClient.setTaskSyncToken(projectId: projectId, token: token)
            oauthToken = ""
            message = "OAuth token saved"
        }
    }

    private func discover() {
        perform {
            let result = try await apiClient.discoverTaskSync(
                projectId: projectId,
                request: APIProjectTaskSyncDiscoverRequest(source: source)
            )
            message = result.statusOptions.isEmpty ? "Source resolved" : "Statuses: \(result.statusOptions.joined(separator: ", "))"
        }
    }

    private func link() {
        perform {
            let response = try await apiClient.linkTaskSync(
                projectId: projectId,
                request: APIProjectTaskSyncLinkRequest(
                    source: source,
                    statusMappings: mappings(outboundMappings),
                    inboundStatusMappings: mappings(inboundMappings),
                    syncSchedule: APIProjectTaskSyncSchedule(
                        enabled: true,
                        intervalMinutes: max(1, Int(intervalMinutes) ?? 5)
                    )
                )
            )
            health = response.settings.health.status
            message = response.settings.health.message ?? "Linked"
        }
    }

    private func syncNow() {
        perform {
            let result = try await apiClient.syncTasksNow(projectId: projectId)
            message = result.message ?? "Imported \(result.imported), updated \(result.updated)"
            health = result.message == nil ? "ok" : "error"
        }
    }

    private func unlink() {
        perform {
            let result = try await apiClient.unlinkTaskSync(projectId: projectId)
            health = result.settings.health.status
            message = "Unlinked"
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            do {
                try await operation()
            } catch {
                health = "error"
                message = error.localizedDescription
            }
        }
    }
}
