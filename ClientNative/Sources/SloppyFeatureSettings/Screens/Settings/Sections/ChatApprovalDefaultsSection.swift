import SwiftUI
import SloppyClientCore
import SloppyClientUI

struct ChatApprovalDefaultsSection: View {
    let apiClient: SloppyAPIClient
    var onSaved: (ChatApprovalMode) -> Void = { _ in }
    @State private var savedMode: ChatApprovalMode?
    @State private var mode = ChatApprovalMode.askForApproval
    @State private var isBusy = true
    @State private var errorMessage: String?

    var body: some View {
        SettingsSectionCard("New chats") {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Default approval mode", selection: $mode) {
                    ForEach(ChatApprovalMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .disabled(isBusy || savedMode == nil)
                .accessibilityIdentifier("settings.default-chat-approval-mode")
                Text("Applies to new chats on this server in ClientNative, Dashboard and TUI. Existing chats keep their mode; delegated sessions inherit their parent chat.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(mode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                    Button("Retry") { Task { await load() } }.disabled(isBusy)
                }
                Button(isBusy ? "Updating…" : "Save") { Task { await save() } }
                    .disabled(isBusy || savedMode == nil || savedMode == mode)
                    .accessibilityIdentifier("settings.default-chat-approval-save")
            }
            .padding(16)
        }
        .task { await load() }
    }

    private func load() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let policy = try await apiClient.fetchDefaultChatApprovalPolicy()
            savedMode = policy.mode
            mode = policy.mode
            errorMessage = nil
        } catch {
            errorMessage = (error as? APIError)?.statusCode == 404
                ? "Update Sloppy Core to configure the default for new chats."
                : "Could not load the default approval mode: \(error.localizedDescription)"
        }
    }

    private func save() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let policy = try await apiClient.setDefaultChatApprovalPolicy(mode: mode)
            savedMode = policy.mode
            mode = policy.mode
            errorMessage = nil
            onSaved(policy.mode)
        } catch {
            errorMessage = (error as? APIError)?.statusCode == 404
                ? "Update Sloppy Core to configure the default for new chats."
                : "Could not save the default approval mode: \(error.localizedDescription)"
        }
    }
}
