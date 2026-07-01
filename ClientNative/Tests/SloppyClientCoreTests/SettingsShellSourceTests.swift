import Foundation
import Testing

@Suite("Settings shell source")
struct SettingsShellSourceTests {
    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    @Test("settings screen defines desktop shell with searchable sidebar")
    func settingsScreenDefinesDesktopShellWithSearchableSidebar() throws {
        let sourceText = try source("Sources/SloppyFeatureSettings/SettingsScreen.swift")

        #expect(sourceText.contains("@State private var searchQuery: String = \"\""))
        #expect(sourceText.contains("private var desktopShell: some View"))
        #expect(sourceText.contains("private var settingsSidebar: some View"))
        #expect(sourceText.contains(".searchable(text: $searchQuery"))
        #expect(sourceText.contains("prompt: \"Search settings...\""))
        #expect(sourceText.contains("filteredSections"))
        #expect(sourceText.contains("groupedFilteredSections"))
    }

    @Test("settings shell uses minimal desktop styling")
    func settingsShellUsesMinimalDesktopStyling() throws {
        let screen = try source("Sources/SloppyFeatureSettings/SettingsScreen.swift")
        let forms = try source("Sources/SloppyFeatureSettings/SettingsFormComponents.swift")
        let client = try source("Sources/SloppyFeatureSettings/ClientSettingsSection.swift")

        #expect(!screen.contains("Color.white.opacity(0.04)"))
        #expect(!client.contains("SectionHeader(\"Client\""))
        #expect(forms.contains("Toggle(isOn:"))
        #expect(forms.contains(".textFieldStyle(.roundedBorder)"))
    }

    @Test("settings screen exposes dashboard section inventory")
    func settingsScreenExposesDashboardSectionInventory() throws {
        let sourceText = try source("Sources/SloppyFeatureSettings/SettingsScreen.swift")

        #expect(sourceText.contains("enum SettingsScreenSection"))
        #expect(sourceText.contains("case providers"))
        #expect(sourceText.contains("case searchTools"))
        #expect(sourceText.contains("case channels"))
        #expect(sourceText.contains("case plugins"))
        #expect(sourceText.contains("case nodeHost"))
        #expect(sourceText.contains("case visor"))
        #expect(sourceText.contains("case acp"))
        #expect(sourceText.contains("case proxy"))
        #expect(sourceText.contains("case gitSync"))
        #expect(sourceText.contains("case rawConfig"))
        #expect(sourceText.contains("case modelRouting"))
        #expect(sourceText.contains("case sessions"))
        #expect(sourceText.contains("case approvals"))
        #expect(sourceText.contains("case mcp"))
        #expect(sourceText.contains("case browser"))
        #expect(sourceText.contains("case voiceMode"))
        #expect(sourceText.contains("case tui"))
        #expect(sourceText.contains("case ui"))
        #expect(sourceText.contains("case compactor"))
        #expect(sourceText.contains("case connectClient"))
        #expect(sourceText.contains("case updates"))
    }

    @Test("settings screen renders detail pane cards or placeholders per section")
    func settingsScreenRendersDetailPaneCardsOrPlaceholdersPerSection() throws {
        let sourceText = try source("Sources/SloppyFeatureSettings/SettingsScreen.swift")

        #expect(sourceText.contains("switch selectedSection"))
        #expect(sourceText.contains("ClientSettingsSection("))
        #expect(sourceText.contains("MeshSettingsSection("))
        #expect(sourceText.contains("ProvidersSection("))
        #expect(sourceText.contains("SearchToolsSection("))
        #expect(sourceText.contains("ChannelsSection("))
        #expect(sourceText.contains("PluginsSection("))
        #expect(sourceText.contains("NodeHostSection("))
        #expect(sourceText.contains("VisorSection("))
        #expect(sourceText.contains("ACPSection("))
        #expect(sourceText.contains("ProxySection("))
        #expect(sourceText.contains("GitSyncSection("))
        #expect(sourceText.contains("RawConfigSection("))
        #expect(sourceText.contains("ModelRoutingSection("))
        #expect(sourceText.contains("BrowserSection("))
        #expect(sourceText.contains("MCPSection("))
        #expect(sourceText.contains("UISection("))
        #expect(sourceText.contains("TUISection("))
        #expect(sourceText.contains("CompactorSection("))
        #expect(sourceText.contains("ConnectClientSection("))
        #expect(sourceText.contains("ApprovalsSection("))
        #expect(sourceText.contains("UnsupportedSettingsSectionView("))
    }
}
