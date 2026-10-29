import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct WorkspaceAction: View {
    let title: String
    var icon: MaterialSymbol? = nil
    var primary = false
    let action: @MainActor () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon { Icons.symbol(icon, size: 16) }
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }
            .foregroundColor(primary ? theme.colors.background : theme.colors.textPrimary)
            .padding(.horizontal, 13).frame(height: 32)
            .background { RoundedRectangle(cornerRadius: 8).fill(primary ? theme.colors.textPrimary : theme.colors.surfaceRaised) }
        }
    }
}

struct WorkspaceIconButton: View {
    let icon: MaterialSymbol
    let action: @MainActor () -> Void
    @Environment(\.theme) private var theme
    var body: some View {
        Button(action: action) {
            Icons.symbol(icon, size: 19).foregroundColor(theme.colors.textSecondary).frame(width: 36, height: 36)
        }
    }
}

struct WorkspaceSearch: View {
    let placeholder: String
    let value: Binding<String>
    @Environment(\.theme) private var theme
    var body: some View {
        HStack(spacing: 8) {
            Icons.symbol(.search, size: 15).foregroundColor(theme.colors.textMuted)
            TextField(placeholder, text: value).textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 13)).foregroundColor(theme.colors.textPrimary)
            if !value.wrappedValue.isEmpty {
                WorkspaceIconButton(icon: .close) { value.wrappedValue = "" }
            }
        }.padding(.horizontal, 12).frame(height: 36)
            .background { RoundedRectangle(cornerRadius: 16).stroke(theme.colors.border, lineWidth: 1) }
    }
}

struct WorkspaceEmpty: View {
    let icon: MaterialSymbol
    let title: String
    let message: String
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(spacing: 16) {
            Icons.symbol(icon, size: 38).foregroundColor(theme.colors.textMuted)
            Text(title).font(.system(size: 24, weight: .semibold)).foregroundColor(theme.colors.textPrimary)
            Text(message).font(.system(size: 14)).foregroundColor(theme.colors.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WorkspacePanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(theme.colors.textSecondary)
            content()
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background { RoundedRectangle(cornerRadius: 13).stroke(theme.colors.border, lineWidth: 1) }
    }
}

struct WorkspaceFilters: View {
    let options: [String]
    let selection: Binding<String>
    @Environment(\.theme) private var theme
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button { selection.wrappedValue = option } label: {
                    Text(option).font(.system(size: 12)).lineLimit(1)
                        .foregroundColor(selection.wrappedValue == option ? theme.colors.background : theme.colors.textSecondary)
                        .padding(.horizontal, 12).frame(height: 26)
                        .background { RoundedRectangle(cornerRadius: 6).fill(selection.wrappedValue == option ? theme.colors.textPrimary : .clear) }
                }
            }
        }.background { RoundedRectangle(cornerRadius: 6).fill(theme.colors.surfaceRaised) }
    }
}

struct WorkspaceToolbar: View {
    let viewModel: MainViewModel
    let showsSidebarControl: Bool
    @Environment(\.theme) private var theme
    var body: some View {
        HStack(spacing: 8) {
            if showsSidebarControl { WorkspaceIconButton(icon: .menu, action: viewModel.openMobileSidebar) }
            Spacer(minLength: 12)
            WorkspaceSearch(placeholder: "Search chats and projects", value: Binding(
                get: { viewModel.searchText }, set: { viewModel.searchText = $0 }
            )).frame(width: showsSidebarControl ? nil : 420).accessibilityIdentifier("workspace.search")
            Spacer(minLength: 12)
            WorkspaceIconButton(icon: .notification) { viewModel.selectSection(.attention) }
                .accessibilityIdentifier("workspace.attention")
            WorkspaceIconButton(icon: .sidePanel) { viewModel.showsInspector.toggle() }
                .accessibilityIdentifier("workspace.inspector.toggle")
            WorkspaceIconButton(icon: .add, action: viewModel.selectNewChat)
        }.padding(.horizontal, 12).frame(height: 52)
    }
}
