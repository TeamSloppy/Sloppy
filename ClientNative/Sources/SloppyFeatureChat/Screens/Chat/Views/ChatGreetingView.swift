import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI

public struct ChatGreetingView: View {
    public let projects: [APIProjectRecord]
    public let selectedProjectId: String?
    public let selectedProjectName: String?
    public let onSelectProject: @MainActor (APIProjectRecord) -> Void
    public let onSelectPrompt: @MainActor (String) -> Void

    public init(
        projects: [APIProjectRecord],
        selectedProjectId: String?,
        selectedProjectName: String?,
        onSelectProject: @escaping @MainActor (APIProjectRecord) -> Void,
        onSelectPrompt: @escaping @MainActor (String) -> Void
    ) {
        self.projects = projects
        self.selectedProjectId = selectedProjectId
        self.selectedProjectName = selectedProjectName
        self.onSelectProject = onSelectProject
        self.onSelectPrompt = onSelectPrompt
    }

    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme

    public var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography
        let isPhone = idiom == .phone

        return VStack(alignment: .center, spacing: isPhone ? sp.l : sp.xxl) {
            SloppyAssets.projectLogo
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundColor(c.textMuted)
                .frame(width: isPhone ? 28 : 38, height: isPhone ? 28 : 38)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: sp.xs) {
                    Text("What should we do in")
                    projectPicker
                    Text("?")
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(spacing: sp.xs) {
                    Text("What should we do in")
                    HStack(alignment: .firstTextBaseline, spacing: sp.xs) {
                        projectPicker
                        Text("?")
                    }
                }
            }
            .font(.system(size: ty.title))
            .foregroundColor(c.textPrimary)
            .lineLimit(1)
            .multilineTextAlignment(.center)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: sp.s), count: isPhone ? 2 : 4),
                spacing: sp.s
            ) {
                ForEach(Self.starterPrompts) { prompt in
                    Button {
                        onSelectPrompt(prompt.prompt)
                    } label: {
                        VStack(alignment: .leading, spacing: sp.l) {
                            Image(systemName: prompt.symbol)
                                .font(.system(size: ty.heading, weight: .medium))
                                .foregroundColor(prompt.color)
                            Text(prompt.title)
                                .font(.system(size: isPhone ? ty.caption : ty.body, weight: .medium))
                                .foregroundColor(c.textPrimary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                        }
                        .padding(isPhone ? sp.s : sp.m)
                        .frame(maxWidth: .infinity, minHeight: isPhone ? 116 : 150, alignment: .leading)
                        .backportGlassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, isPhone ? sp.s : sp.m)
    }

    private var projectPicker: some View {
        Menu {
            if projects.isEmpty {
                Text("No projects")
            } else {
                ForEach(projects) { project in
                    Button(project.name) {
                        onSelectProject(project)
                    }
                }
            }
        } label: {
            Text(projectPickerTitle)
                .underline(pattern: .dot)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose project")
    }

    private var projectPickerTitle: String {
        selectedProjectName
            ?? projects.first(where: { $0.id == selectedProjectId })?.name
            ?? "Select project"
    }

    private struct StarterPrompt: Identifiable {
        let title: String
        let prompt: String
        let symbol: String
        let color: Color

        var id: String { title }
    }

    private static let starterPrompts = [
        StarterPrompt(
            title: "Explore and understand code",
            prompt: "Explore this project and explain how it is structured.",
            symbol: "binoculars",
            color: .blue
        ),
        StarterPrompt(
            title: "Build a new feature, app, or tool",
            prompt: "Help me build a new feature in this project.",
            symbol: "hammer",
            color: .purple
        ),
        StarterPrompt(
            title: "Review code and suggest changes",
            prompt: "Review this project's code and suggest improvements.",
            symbol: "arrow.triangle.2.circlepath",
            color: .green
        ),
        StarterPrompt(
            title: "Fix issues and failures",
            prompt: "Find and fix the current issues in this project.",
            symbol: "ant",
            color: .orange
        ),
    ]
}

#Preview {
    ChatGreetingView(projects: [
        .init(id: "sloppy", name: "Sloppy"),
        .init(id: "adaengine", name: "AdaEngine"),
    ], selectedProjectId: "sloppy", selectedProjectName: "Sloppy") { _ in

    } onSelectPrompt: { _ in

    }
    .frame(width: 500, height: 900)
}
