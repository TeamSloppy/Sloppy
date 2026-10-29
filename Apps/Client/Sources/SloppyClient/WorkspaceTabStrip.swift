import AdaEngine
import SloppyClientUI

@MainActor
struct WorkspaceTabStrip: View {
    let viewModel: MainViewModel
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, respectsSafeArea: false) {
                HStack(spacing: 4) {
                    ForEach(viewModel.navigation.tabs) { tab in
                        tabButton(tab.id, title: tab.title)
                    }
                }
            }
            Button(action: viewModel.selectNewChat) {
                Icons.symbol(.add, size: 18)
                    .foregroundColor(theme.colors.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("workspace.newChat")
        }
        .padding(.horizontal, 8)
        .frame(height: 48)
        .background(theme.colors.surface)
        .overlay(anchor: .bottom) { theme.colors.border.frame(height: 1) }
    }

    private func tabButton(_ id: UUID, title: String) -> some View {
        let selected = viewModel.navigation.section == .chats && viewModel.navigation.selectedTabID == id
        return HStack(spacing: 0) {
            Button { viewModel.selectTab(id) } label: {
                HStack(spacing: 8) {
                    Icons.symbol(.chatAddOn, size: 15)
                    Text(title).font(.system(size: 13)).lineLimit(1)
                }
                .foregroundColor(selected ? theme.colors.textPrimary : theme.colors.textMuted)
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .frame(height: 36)
            }
            .accessibilityIdentifier("workspace.tab.\(id)")
            Button { viewModel.closeTab(id) } label: {
                Icons.symbol(.close, size: 12)
                    .foregroundColor(theme.colors.textMuted)
                    .frame(width: 32, height: 36)
            }
            .accessibilityIdentifier("workspace.closeTab.\(id)")
        }
        .frame(maxWidth: 240)
        .background(selected ? theme.colors.background : Color.clear)
    }
}
