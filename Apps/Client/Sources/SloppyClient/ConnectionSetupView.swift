import AdaEngine
import SloppyClientCore
import SloppyClientUI
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct ConnectionSetupView: View {
    let settings: ClientSettings
    let onConnected: (URL) -> Void

    @State private var hostDraft: String = ""
    @State private var portDraft: String = "25101"
    @State private var discoveredServers: [SavedServer] = []
    @State private var isScanning = false
    @State private var isConnecting = false
    @State private var errorMessage: String?

    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography
        let bo = theme.borders

        return ScrollView {
            VStack(alignment: .leading, spacing: sp.xxl) {

                // Header
                VStack(alignment: .leading, spacing: sp.s) {
                    Icons.symbol(.autoAwesome, size: 32)
                        .foregroundColor(c.accent)
                    Text("Connect to Sloppy")
                        .font(.system(size: ty.title))
                        .foregroundColor(c.accent)
                    Text("No server found automatically. Set up your connection below.")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.textMuted)
                }

                // Warning banner
                HStack(spacing: sp.s) {
                    Icons.symbol(.warning, size: ty.caption)
                        .foregroundColor(c.statusWarning)
                    Text("Local network scan only works on your current Wi-Fi.\nFor remote access, enter the address manually.")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.statusWarning)
                }
                .padding(sp.m)
                .background(c.statusWarning.opacity(0.08))
                .border(c.statusWarning.opacity(0.3), lineWidth: bo.thin)

                // Scan section
                VStack(alignment: .leading, spacing: sp.m) {
                    HStack {
                        Text("LOCAL NETWORK")
                            .font(.system(size: ty.caption))
                            .foregroundColor(c.textMuted)
                        Spacer()
                        Button(isScanning ? "SCANNING..." : "SCAN") {
                            startScan()
                        }
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.accentCyan)
                        .disabled(isScanning)
                    }

                    if discoveredServers.isEmpty && !isScanning {
                        Text("No servers found. Try scanning or enter manually.")
                            .font(.system(size: ty.caption))
                            .foregroundColor(c.textMuted)
                    }

                    ForEach(discoveredServers) { server in
                        Button(action: { connect(to: server.baseURL) }) {
                            HStack(spacing: sp.m) {
                                VStack(alignment: .leading, spacing: sp.xs) {
                                    Text(server.label)
                                        .font(.system(size: ty.body))
                                        .foregroundColor(c.textPrimary)
                                    Text("\(server.host):\(server.port)")
                                        .font(.system(size: ty.micro))
                                        .foregroundColor(c.textMuted)
                                }
                                Spacer()
                                HStack(spacing: sp.xs) {
                                    Text("CONNECT")
                                        .font(.system(size: ty.caption))
                                    Icons.symbol(.arrowForward, size: ty.caption)
                                }
                                .foregroundColor(c.accentCyan)
                            }
                            .padding(sp.m)
                            .background(c.surface)
                            .border(c.accentCyan.opacity(0.3), lineWidth: bo.thin)
                        }
                    }
                }

                // Manual input section
                VStack(alignment: .leading, spacing: sp.m) {
                    Text("MANUAL")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.textMuted)

                    Text("On a physical iPhone or iPad, “localhost” is the device itself, not your Mac. Use your computer’s LAN address (for example 192.168.x.x) or run Sloppy Core on the same device.")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.textMuted)

                    VStack(alignment: .leading, spacing: 0) {
                        manualField("Host", hint: "192.168.1.50 or hostname", text: $hostDraft)
                        Color.clear.frame(height: bo.thin).background(c.border)
                        manualField("Port", hint: "25101", text: $portDraft)
                    }
                    .background(c.surface)
                    .border(c.border, lineWidth: bo.thin)

                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: ty.caption))
                            .foregroundColor(c.statusBlocked)
                    }

                    HStack {
                        Spacer()
                        Button(isConnecting ? "CONNECTING..." : "CONNECT") {
                            connectManual()
                        }
                        .font(.system(size: ty.body))
                        .foregroundColor(c.background)
                        .padding(.horizontal, sp.l)
                        .padding(.vertical, sp.s)
                        .background(c.accentCyan)
//                        .disabled(isConnecting || hostDraft.isEmpty)
                    }
                }

                // QR code hint
                VStack(alignment: .leading, spacing: sp.s) {
                    Text("QR CODE")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.textMuted)
                    Text("Open the Sloppy Dashboard in a browser and navigate to \nSettings > Connect Client to display a QR code. Scan it with your device camera to connect automatically.")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.textSecondary)
                }
                .padding(sp.m)
                .background(c.surface)
                .border(c.border, lineWidth: bo.thin)
            }
            .padding(theme.spacing.l)
        }
        .background(theme.colors.background)
        .onAppear {
            hostDraft = settings.serverHost == "localhost" ? "" : settings.serverHost
            portDraft = String(settings.serverPort)
            startScan()
        }
    }

    private func manualField(_ label: String, hint: String, text: Binding<String>) -> some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return HStack(spacing: sp.m) {
            Text(label.uppercased())
                .font(.system(size: ty.caption))
                .foregroundColor(c.textMuted)
                .frame(width: 40)
            TextField(hint, text: text)
                .font(.system(size: ty.body))
                .foregroundColor(.white)
                .textFieldStyle(PlainTextFieldStyle())
        }
        .padding(.horizontal, sp.m)
        .padding(.vertical, sp.s)
    }

    private func startScan() {
        guard !isScanning else { return }
        isScanning = true
        discoveredServers = []
        Task { @MainActor in
            let scanner = LocalNetworkScanner()
            for await server in await scanner.scan() {
                discoveredServers.append(server)
            }
            isScanning = false
        }
    }

    private func connect(to url: URL) {
        guard !isConnecting else { return }
        isConnecting = true
        Task { @MainActor in
            let ok = await checkHealth(url: url)
            isConnecting = false
            if ok {
                let server = SavedServer(label: "Discovered", host: url.host ?? "", port: url.port ?? 25101, isAutoDiscovered: true)
                settings.useServer(server)
                onConnected(url)
            } else {
                errorMessage = "Could not connect to \(url.host ?? "server")"
            }
        }
    }

    private func connectManual() {
        errorMessage = nil
        guard let address = ServerAddress.parse(host: hostDraft, port: portDraft) else { return }

        isConnecting = true
        Task { @MainActor in
            let url = address.baseURL
            let ok = await checkHealth(url: url)
            isConnecting = false
            if ok {
                let server = SavedServer(label: "Sloppy @ \(address.host)", host: address.host, port: address.port)
                settings.useServer(server)
                onConnected(url)
            } else {
                errorMessage = "Could not connect to \(address.host):\(address.port)"
            }
        }
    }

    private func checkHealth(url: URL) async -> Bool {
        let endpoint = url.appendingPathComponent("/health")
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }
}
