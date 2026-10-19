import SwiftUI
import SloppyClientCore
import SloppyClientUI

struct ChatApprovalModePicker: View {
    let viewModel: ChatScreenViewModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                ForEach(ChatApprovalMode.allCases, id: \.self) { mode in
                    Button {
                        viewModel.selectApprovalMode(mode)
                    } label: {
                        Label(mode.title, systemImage: viewModel.selectedApprovalMode == mode ? "checkmark" : "shield")
                        Text(mode.detail)
                    }
                }
            } label: {
                Label(labelTitle, systemImage: viewModel.selectedApprovalMode == .approveForMe ? "checkmark.shield" : "hand.raised")
                .font(.caption)
                .foregroundStyle(theme.colors.textMuted)
            }
            .menuStyle(.borderlessButton)
            .tint(theme.colors.textMuted)
            .fixedSize()
            .disabled(viewModel.isSavingApprovalMode || viewModel.isLoadingApprovalMode || viewModel.isSending || viewModel.selectedAgent == nil)
            .help(viewModel.selectedApprovalMode.detail)
            .accessibilityLabel("Action approval mode")
            .accessibilityValue(viewModel.selectedApprovalMode.title)
            .accessibilityIdentifier("chat.composer.approval-mode")

            if let error = viewModel.approvalModeErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(theme.colors.statusBlocked)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("chat.composer.approval-mode-error")
                Button("Retry") { viewModel.reloadApprovalMode() }
                    .font(.caption)
            }
        }
    }

    private var labelTitle: String {
        var title = viewModel.selectedApprovalMode.title
        if viewModel.selectedApprovalMode == .approveForMe { title += " · JEV" }
        if viewModel.isSavingApprovalMode || viewModel.isLoadingApprovalMode { title += "…" }
        return title
    }
}
