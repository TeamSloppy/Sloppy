import AdaEngine
import SloppyClientCore
import SloppyClientUI

enum SplashResult {
    case connected(URL)
    case needsSetup
}

struct SplashScreen: View {
    let settings: ClientSettings
    let onResult: (SplashResult) -> Void

    @State private var status: String = "Connecting..."
    @State private var isScanning = false
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return VStack(alignment: .leading, spacing: sp.xxl) {
            Spacer()

            VStack(alignment: .leading, spacing: sp.m) {
                Text("✦")
                    .font(.system(size: Double(64)))
                    .foregroundColor(c.accent)

                Text("Sloppy")
                    .font(.system(size: ty.hero))
                    .foregroundColor(c.textPrimary)
            }
            .padding(.horizontal, sp.xxl)

            VStack(alignment: .leading, spacing: sp.s) {
                Text(status.uppercased())
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)

                if isScanning {
                    Text("Scanning local network...")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.textMuted)
                }
            }
            .padding(.horizontal, sp.xxl)

            Spacer()
        }
        .background(c.background)
        .onAppear { attemptConnection() }
    }

    private func attemptConnection() {
        Task { @MainActor in
            // 1. Try saved server address
            if !settings.savedServers.isEmpty || settings.serverHost != "localhost" {
                status = "Trying saved server..."
                let url = settings.baseURL
                if await checkHealth(url: url) {
                    onResult(.connected(url))
                    return
                }
            }

            // 2. Scan local network
            status = "Scanning network..."
            isScanning = true
            let scanner = LocalNetworkScanner()
            var found: SavedServer?
            for await server in await scanner.scan() {
                found = server
                break
            }
            isScanning = false

            if let server = found {
                status = "Found \(server.host)"
                settings.useServer(server)
                onResult(.connected(server.baseURL))
                return
            }

            // 3. Give up -- show setup
            status = "No server found"
            try? await Task.sleep(nanoseconds: 800_000_000)
            onResult(.needsSetup)
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
