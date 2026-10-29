import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct ProactivityPreferences: View {
    let api: SloppyAPIClient
    @State private var agents: [APIAgentRecord] = []
    @State private var selectedID = ""
    @State private var document: ConfigJSONValue?
    @State private var status = ""
    @State private var busy = false
    @State private var generation = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal, respectsSafeArea: false) {
                HStack(spacing: 12) {
                    ForEach(agents) { agent in
                        Button(agent.displayName) { select(agent.id) }.disabled(busy)
                    }
                }
            }.frame(height: 36)
            Text(status).font(.system(size: 12)).textSelection(.enabled)
            if let document {
                ConfigValueEditor(document) { updated in
                    guard !busy else { return }; busy = true
                    let agentID = selectedID
                    Task {
                        defer { busy = false }
                        do {
                            self.document = try await api.workspace.updateProactiveSettings(agentID: agentID, document: updated)
                            generation += 1; status = "Saved"
                        } catch { status = error.localizedDescription }
                    }
                }.id("\(selectedID):\(generation)").disabled(busy)
            }
        }.onAppear {
            Task {
                do { agents = try await api.fetchAgents(); if let first = agents.first { select(first.id) } }
                catch { status = error.localizedDescription }
            }
        }
    }
    private func select(_ id: String) {
        selectedID = id; document = nil; status = "Loading…"; busy = true
        Task {
            defer { busy = false }
            do {
                let response = try await api.workspace.proactiveSettings(agentID: id)
                // Catalog/model metadata stays outside the editable heartbeat document.
                document = .object(["heartbeat": response["heartbeat"], "heartbeatMarkdown": response["heartbeatMarkdown"]])
                generation += 1; status = "Background checks for \(id)"
            } catch { status = error.localizedDescription }
        }
    }
}

struct SessionPreferences: View {
    let api: SloppyAPIClient
    @State private var sessions: [ChatSessionSummary] = []
    @State private var query = ""
    @State private var status = ""
    @State private var removal: String?
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Search conversation history", text: $query).font(.system(size: 13)).padding(.horizontal, 8).frame(height: 36)
            Button("Refresh") { load() }.disabled(busy)
            Text(status).font(.system(size: 12)).textSelection(.enabled)
            ForEach(sessions.filter { query.isEmpty || ($0.title + " " + $0.agentId).localizedCaseInsensitiveContains(query) }) { session in
                SettingsSectionCard(session.title.isEmpty ? "Untitled chat" : session.title) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(session.agentId) · \(session.updatedAt.formatted())").font(.system(size: 12))
                        Text(session.id).textSelection(.enabled).font(.system(size: 11))
                        if removal == session.id {
                            Text("Permanently delete this conversation?").font(.system(size: 13))
                            HStack {
                                Button("Delete conversation") { remove(session) }.disabled(busy)
                                Button("Cancel") { removal = nil }
                            }
                        } else { Button("Delete…") { removal = session.id } }
                    }.padding(14)
                }
            }
        }.onAppear { load() }
    }
    private func load() {
        guard !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do { sessions = try await api.fetchSessionMentions(query: ""); status = "\(sessions.count) recent conversations" }
            catch { status = error.localizedDescription }
        }
    }
    private func remove(_ session: ChatSessionSummary) {
        guard !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do { try await api.deleteAgentSession(agentId: session.agentId, sessionId: session.id); sessions.removeAll { $0.id == session.id }; removal = nil }
            catch { status = error.localizedDescription }
        }
    }
}

struct ConnectionPreferences: View {
    let settings: ClientSettings
    @State private var host = ""
    @State private var status = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsFieldRow("Server host", text: $host)
            Text(connectionURL?.absoluteString ?? "Enter a valid server host").textSelection(.enabled).font(.system(size: 13))
            Button("Copy connection link") {
                if let url = connectionURL { UIClipboard.setString(url.absoluteString); status = "Copied" }
            }.disabled(connectionURL == nil)
            Text(status).font(.system(size: 12))
            Text("Saved servers").font(.system(size: 18, weight: .semibold))
            ForEach(settings.savedServers) { server in
                Text("\(server.label) · \(server.host):\(server.port)").font(.system(size: 13))
            }
        }.onAppear { host = settings.serverHost }
    }
    private var connectionURL: URL? {
        guard let address = ServerAddress.parse(host: host, port: String(settings.serverPort)) else { return nil }
        var components = URLComponents(); components.scheme = "sloppy"; components.host = "connect"
        components.queryItems = [URLQueryItem(name: "host", value: address.host), URLQueryItem(name: "port", value: String(address.port))]
        return components.url
    }
}

struct ServiceStatusPreferences: View {
    let service: WorkspaceService
    let isVoice: Bool
    @State private var content = "Loading…"
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Refresh") { load() }.disabled(busy)
            Text(content).font(.monospaced(size: 13)).textSelection(.enabled)
        }.onAppear { load() }
    }
    private func load() {
        guard !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do { content = try await (isVoice ? service.voiceConfiguration() : service.meshTopology()).formatted }
            catch { content = error.localizedDescription }
        }
    }
}
