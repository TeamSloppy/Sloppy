import Foundation
import SwiftUI
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

        return VStack(spacing: sp.xxl) {
            Spacer()

            VStack(spacing: sp.m) {
                SloppyAssets.projectLogo
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .foregroundColor(c.textMuted)

                Text("Sloppy")
                    .font(.system(size: ty.hero))
                    .foregroundColor(c.textPrimary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: sp.s) {
                Text(status.uppercased())
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)
                    .multilineTextAlignment(.center)

                if isScanning {
                    Text("Scanning local network...")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.textMuted)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear { attemptConnection() }
    }

    private func attemptConnection() {
        Task { @MainActor in
            // 1. Try configured host:port (includes default localhost:25101 on first launch).
            status = "Trying \(settings.serverHost):\(settings.serverPort)..."
            let url = settings.baseURL
            if await HealthService(baseURL: url).isHealthy() {
                onResult(.connected(url))
                return
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
}
