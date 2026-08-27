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

    @Test("settings screen defines adaptive split shell with searchable sidebar")
    func settingsScreenDefinesAdaptiveSplitShellWithSearchableSidebar() throws {
        let sourceText = try source("Sources/SloppyFeatureSettings/Screens/Settings/SettingsScreen.swift")

        #expect(sourceText.contains("@State private var searchQuery: String = \"\""))
        #expect(sourceText.contains("private var settingsShell: some View"))
        #expect(sourceText.contains("NavigationSplitView(preferredCompactColumn:"))
        #expect(sourceText.contains("@State private var selectedSection: SettingsScreenSection?"))
        #expect(sourceText.contains("self._selectedSection = State(initialValue: nil)"))
        #expect(sourceText.contains("private var settingsSidebar: some View"))
        #expect(sourceText.contains(".searchable(text: $searchQuery"))
        #expect(sourceText.contains("prompt: \"Search settings...\""))
        #expect(sourceText.contains("filteredSections"))
        #expect(sourceText.contains("groupedFilteredSections"))
    }

    @Test("general settings show a read-only server and change-server action")
    func generalSettingsShowReadOnlyServerAndChangeServerAction() throws {
        let client = try source(
            "Sources/SloppyFeatureSettings/Screens/Settings/Sections/ClientSettingsSection.swift"
        )

        #expect(client.contains("Text(settings.serverHost)"))
        #expect(client.contains("Label(\"Change Server\""))
        #expect(client.contains("Changing server signs you out"))
        #expect(client.contains("settings.change-server"))
        #expect(!client.contains("SettingsFieldRow(\"Host\""))
        #expect(!client.contains("SettingsFieldRow(\"Port\""))
        #expect(!client.contains("Button(\"Apply\")"))
    }

    @Test("settings sidebar uses native list selection rows")
    func settingsSidebarUsesNativeListSelectionRows() throws {
        let sourceText = try source("Sources/SloppyFeatureSettings/Screens/Settings/SettingsScreen.swift")

        #expect(sourceText.contains("List(selection: $selectedSection)"))
        #expect(sourceText.contains(".tag(section)"))
        #expect(sourceText.contains(".listStyle(.sidebar)"))
    }

    @Test("settings shell uses minimal desktop styling")
    func settingsShellUsesMinimalDesktopStyling() throws {
        let screen = try source("Sources/SloppyFeatureSettings/Screens/Settings/SettingsScreen.swift")
        let forms = try source("Sources/SloppyFeatureSettings/Screens/Settings/Views/SettingsFormComponents.swift")
        let client = try source("Sources/SloppyFeatureSettings/Screens/Settings/Sections/ClientSettingsSection.swift")

        #expect(!screen.contains("Color.white.opacity(0.04)"))
        #expect(!client.contains("SectionHeader(\"Client\""))
        #expect(forms.contains("Toggle(isOn:"))
        #expect(forms.contains(".textFieldStyle(.roundedBorder)"))
    }

    @Test("settings screen exposes dashboard section inventory")
    func settingsScreenExposesDashboardSectionInventory() throws {
        let sourceText = try source("Sources/SloppyFeatureSettings/Screens/Settings/SettingsScreen.swift")

        #expect(sourceText.contains("enum SettingsScreenSection"))
        #expect(sourceText.contains("case account"))
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
        let sourceText = try source("Sources/SloppyFeatureSettings/Screens/Settings/SettingsScreen.swift")

        #expect(sourceText.contains("switch section"))
        #expect(sourceText.contains("AccountSettingsSection("))
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

    @Test("account settings expose profile and security management")
    func accountSettingsExposeProfileAndSecurityManagement() throws {
        let account = try source(
            "Sources/SloppyFeatureSettings/Screens/Settings/Sections/AccountSettingsSection.swift"
        )
        let sidebar = try source(
            "Sources/SloppyClient/Navigation/Platforms/macOS/MacMainSidebar.swift"
        )

        #expect(account.contains("Save Profile"))
        #expect(account.contains("Change Password"))
        #expect(account.contains("Generate Recovery Codes"))
        #expect(account.contains("Application Tokens"))
        #expect(account.contains("Sign Out"))
        #expect(sidebar.contains("viewModel.onOpenSettings(.account)"))
    }
}
