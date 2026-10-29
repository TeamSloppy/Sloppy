import Foundation

enum SettingsSection: String, CaseIterable, Identifiable {
    case account, approvals, proactivity, sessions, mesh, voiceMode, connectClient
    case general, providers, semanticDecisions, searchTools, channels, plugins, nodes, visor, acp, proxy, gitSync
    case modelRouting, mcp, browser, ui, tui, compactor, memory, toolHooks, experimental, raw
    var id: String { rawValue }
    var group: String {
        switch self {
        case .general, .account, .mesh, .connectClient: "Client"
        case .raw, .toolHooks, .experimental, .memory, .tui, .compactor: "Advanced"
        default: "Sloppy config"
        }
    }
    var title: String {
        switch self {
        case .account: "Account"
        case .approvals: "Approvals"
        case .proactivity: "Proactivity"
        case .sessions: "Sessions"
        case .mesh: "Mesh"
        case .voiceMode: "Voice mode"
        case .connectClient: "Connect client"
        case .general: "General"
        case .providers: "Providers"
        case .semanticDecisions: "Semantic decisions"
        case .searchTools: "Search tools"
        case .channels: "Channels"
        case .plugins: "Plugins"
        case .nodes: "Node host"
        case .visor: "Visor"
        case .acp: "ACP"
        case .proxy: "Proxy"
        case .gitSync: "Git sync"
        case .modelRouting: "Model routing"
        case .mcp: "MCP"
        case .browser: "Browser"
        case .ui: "Dashboard UI"
        case .tui: "Terminal UI"
        case .compactor: "Compactor"
        case .memory: "Memory"
        case .toolHooks: "Tool hooks"
        case .experimental: "Experimental"
        case .raw: "Raw config"
        }
    }
    var subtitle: String {
        switch self {
        case .account: "Profile details for the connected account."
        case .approvals: "Review pending tool requests and channel access users."
        case .proactivity: "Background checks, notification hours, models, and instructions per agent."
        case .sessions: "Browse and remove conversation history."
        case .mesh: "Inspect the connected server's node topology."
        case .voiceMode: "Inspect the server's effective speech configuration."
        case .connectClient: "Copy a connection link for another device."
        case .general: "Connection, appearance, and accent color."
        case .providers: "Configure model providers and choose from the shared model catalog."
        case .semanticDecisions: "Provider, model, confidence, and executor routing."
        case .modelRouting: "Map model aliases to configured providers."
        case .mcp: "Server transports, commands, environment, and exposed capabilities."
        case .browser: "Browser executable, CDP connection, profiles, and startup behavior."
        case .compactor: "Context limits, compaction thresholds, and retry policy."
        case .memory: "Retrieval weights and retention policy."
        case .toolHooks: "Configure the pre-tool hook and its failure policy."
        case .raw: "Inspect the configuration. Copy text or select individual values."
        default: "Configure \(title.lowercased()) for the connected Sloppy server."
        }
    }
    func matches(_ query: String) -> Bool {
        query.isEmpty || "\(title) \(subtitle) \(rawValue)".localizedCaseInsensitiveContains(query)
    }
}
