#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SloppyClientCore
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyClient
@testable import SloppyFeatureAgents
@testable import SloppyFeatureProjects
@testable import SloppyFeatureSettings

@Suite("Desktop section appearance", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct DesktopScreensRenderingTests {
    @Test func sectionsRenderWithNeutralSurfacesAndWorkingActions() async throws {
        AppKitTestAccessibility.enable()
        let agents: [APIAgentRecord] = [
            .init(id: "anton", displayName: "Антон", role: "Разработка Swift и AdaEngine"),
            .init(id: "frontend", displayName: "Фронтяра", role: "Интерфейсы и веб-приложения"),
            .init(id: "reviewer", displayName: "Reviewer", role: "Code review and verification"),
        ]
        let projects: [APIProjectRecord] = [
            .init(id: "sloppy", name: "Sloppy", description: "Desktop agent workspace", tasks: [
                .init(id: "design", title: "Unify desktop screens", status: "in_progress"),
                .init(id: "review", title: "Review the new layout", status: "needs_review"),
            ]),
            .init(id: "ada", name: "AdaEngine", description: "Swift game engine and editor"),
        ]
        var submitted = 0
        let form = AnyView(VStack(alignment: .leading, spacing: 24) {
            Text("Settings").font(.largeTitle.weight(.semibold))
            Text("Models and workspace preferences").foregroundStyle(.secondary)
            SettingsSectionCard("Connection") {
                SettingsFieldRow("Server", hint: "Your local Sloppy Core", text: .constant("http://localhost:25101"))
                SettingsDivider()
                SettingsToggleRow(label: "Reconnect automatically", value: true, onToggle: {})
            }
            SettingsSectionCard("Models") {
                SettingsFieldRow("Default model", text: .constant("Claude Sonnet"))
                SettingsDivider()
                SettingsToggleRow(label: "Show tool activity", value: true, onToggle: {})
            }
            HStack {
                Button("Cancel") {}.buttonStyle(.bordered)
                Button("Save changes") { submitted += 1 }
                    .appPrimaryButton()
                    .accessibilityIdentifier("desktop-preview.save")
                Button("Unavailable") { submitted += 100 }
                    .appPrimaryButton().disabled(true)
                    .accessibilityIdentifier("desktop-preview.disabled")
            }
            Spacer()
        }.padding(32).desktopContentWidth(760))
        let cases: [(String, AnyView)] = [
            ("agents", AnyView(AgentListView(agents: agents, snapshots: [:], isLoading: false,
                                             errorMessage: nil, onRefresh: {}))),
            ("projects", AnyView(ProjectListView(projects: projects, isLoading: false, onRefresh: {}))),
            ("settings", form),
        ]
        for (name, content) in cases {
            for scheme in name == "settings" ? [ColorScheme.dark, .light] : [.dark] {
                let host = NSHostingView(rootView: NavigationStack { content }
                    .desktopScreenStyle()
                    .environment(\.theme, scheme == .dark ? .sloppyDark : .sloppyLight)
                    .preferredColorScheme(scheme))
                let window = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 1120, height: 760),
                                      styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.contentView = host
                window.makeKeyAndOrderFront(nil)
                try await Task.sleep(for: .milliseconds(200))
                host.layoutSubtreeIfNeeded()
                if name == "projects" {
                    let first = try #require(AppKitTestAccessibility.element(in: host, identifier: "projects.card.sloppy"))
                    let second = try #require(AppKitTestAccessibility.element(in: host, identifier: "projects.card.ada"))
                    let firstFrame = try #require(AppKitTestAccessibility.frame(of: first))
                    let secondFrame = try #require(AppKitTestAccessibility.frame(of: second))
                    #expect(!firstFrame.intersects(secondFrame))
                    #expect(firstFrame.height >= 72)
                }
                if name == "settings" {
                    let save = try #require(AppKitTestAccessibility.element(in: host, identifier: "desktop-preview.save"))
                    let before = submitted
                    #expect(AppKitTestAccessibility.press(save))
                    #expect(submitted == before + 1)
                    let disabled = try #require(AppKitTestAccessibility.element(in: host, identifier: "desktop-preview.disabled"))
                    _ = AppKitTestAccessibility.press(disabled)
                    #expect(submitted == before + 1)
                }
                if let directory = ProcessInfo.processInfo.environment["SLOPPY_SECTIONS_SCREENSHOTS"] {
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try #require(bitmap.representation(using: .png, properties: [:]))
                        .write(to: URL(fileURLWithPath: directory)
                            .appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
                }
                window.contentView = nil
                window.close()
            }
        }
    }
}
#endif
