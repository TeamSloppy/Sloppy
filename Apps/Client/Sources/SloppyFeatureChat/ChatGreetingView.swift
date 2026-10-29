import AdaEngine
import SloppyClientCore
import SloppyClientUI

public struct ChatGreetingView: View {
    private let availableWidth: Float
    private let projects: [APIProjectRecord]
    private let contextTitle: String
    private let onSelectPersonal: @MainActor () -> Void
    private let onSelectProject: @MainActor (APIProjectRecord) -> Void
    private let onSelectPrompt: @MainActor (String) -> Void
    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme
    @State private var showsContexts = false

    public init(agentName: String) {
        self.init(projects: [], contextTitle: "Personal", onSelectPersonal: {}, onSelectProject: { _ in }, onSelectPrompt: { _ in })
    }

    public init(projects: [APIProjectRecord], contextTitle: String,
                onSelectPersonal: @escaping @MainActor () -> Void,
                onSelectProject: @escaping @MainActor (APIProjectRecord) -> Void,
                onSelectPrompt: @escaping @MainActor (String) -> Void, availableWidth: Float = 720) {
        self.availableWidth = availableWidth
        self.projects = projects
        self.contextTitle = contextTitle
        self.onSelectPersonal = onSelectPersonal
        self.onSelectProject = onSelectProject
        self.onSelectPrompt = onSelectPrompt
    }

    public var body: some View {
        VStack(spacing: 24) {
            GreetingAstronaut().foregroundColor(theme.colors.textMuted)
            HStack(spacing: 7) {
                Text("What should we do in")
                    .font(.system(size: idiom == .phone ? 24 : 30))
                    .foregroundColor(theme.colors.textPrimary)
                    .multilineTextAlignment(.center)
                Button { showsContexts.toggle() } label: {
                    HStack(spacing: 8) {
                        Text(contextTitle).font(.system(size: idiom == .phone ? 24 : 30, weight: .semibold)).lineLimit(2)
                        Icons.symbol(.expandMore, size: 18)
                    }
                    .foregroundColor(theme.colors.accent)
                }
                .accessibilityIdentifier("chat.context.picker")
            }
            if showsContexts {
                VStack(alignment: .leading, spacing: 8) {
                    contextButton("Personal") { onSelectPersonal() }
                    ForEach(projects) { project in contextButton(project.name) { onSelectProject(project) } }
                }
                .padding(12)
                .background(theme.colors.surface)
                .frame(maxWidth: 320)
            }
            if isCompact {
                VStack(spacing: 10) {
                    HStack(spacing: 10) { explore; build }
                    HStack(spacing: 10) { review; fix }
                }
            } else {
                HStack(spacing: 10) { explore; build; review; fix }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 760)
    }

    private func contextButton(_ title: String, action: @escaping @MainActor () -> Void) -> some View {
        Button {
            action()
            showsContexts = false
        } label: {
            Text(title).font(.system(size: 14)).foregroundColor(theme.colors.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        }
    }

    private var isCompact: Bool { idiom == .phone || availableWidth < 600 }

    private var explore: some View { prompt("Explore and understand code", "Explore this project and explain how it is structured.", .search, .fromHex(0x00B8EE)) }
    private var build: some View { prompt("Build a new feature, app, or tool", "Help me build a new feature in this project.", .build, .fromHex(0x00B8EE)) }
    private var review: some View { prompt("Review code and suggest changes", "Review this project's code and suggest improvements.", .refresh, .fromHex(0x00DE63)) }
    private var fix: some View { prompt("Fix issues and failures", "Find and fix the current issues in this project.", .bug, .fromHex(0xED9A20)) }

    private func prompt(_ title: String, _ text: String, _ icon: MaterialSymbol, _ color: Color) -> some View {
        GreetingPrompt(title: title, icon: icon, color: color) { onSelectPrompt(text) }
            .frame(width: max(80, (availableWidth - 32 - (isCompact ? 10 : 30)) / (isCompact ? 2 : 4)))
    }
}

private struct GreetingAstronaut: View {
    @Environment(\.theme) private var theme
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).stroke(theme.colors.textMuted, lineWidth: 2)
                .frame(width: 32, height: 32).offset(y: -3)
            Circle().stroke(theme.colors.textMuted, lineWidth: 2)
                .frame(width: 24, height: 24).offset(y: -5)
            RoundedRectangle(cornerRadius: 3).stroke(theme.colors.textMuted, lineWidth: 2)
                .frame(width: 18, height: 7).offset(y: 17)
            RoundedRectangle(cornerRadius: 2).fill(theme.colors.textMuted)
                .frame(width: 3, height: 11).offset(x: -19, y: 10)
            RoundedRectangle(cornerRadius: 2).fill(theme.colors.textMuted)
                .frame(width: 3, height: 11).offset(x: 19, y: 10)
        }.frame(width: 44, height: 44)
    }
}

private struct GreetingPrompt: View {
    let title: String
    let icon: MaterialSymbol
    let color: Color
    let action: @MainActor () -> Void
    @State private var hovered = false
    @Environment(\.theme) private var theme
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 22) {
                Icons.symbol(icon, size: 24).foregroundColor(color)
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(theme.colors.textPrimary)
                    .multilineTextAlignment(.leading).lineLimit(3)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).frame(height: 150)
                .background { RoundedRectangle(cornerRadius: 20).fill(theme.colors.background) }
                .overlay { RoundedRectangle(cornerRadius: 20).stroke(hovered ? color : theme.colors.border, lineWidth: 1) }
                .shadow(color: hovered ? color.opacity(0.18 as Float) : .black.opacity(0.12 as Float), radius: hovered ? 20 : 8, y: hovered ? 10 : 4, shape: .roundedRectangle(cornerRadius: 20))
        }.onHover { hovered = $0 }
    }
}
