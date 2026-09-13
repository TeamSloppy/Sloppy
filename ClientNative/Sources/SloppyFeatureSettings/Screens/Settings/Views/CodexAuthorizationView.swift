import SwiftUI
import SloppyClientCore

struct CodexAuthorizationView: View {
    let apiClient: SloppyAPIClient?
    let onConnected: () async -> Void

    @Environment(\.openURL) private var openURL
    @State private var authorization: CodexDeviceAuthorization?
    @State private var message = "Sign in with your ChatGPT account using a device code."
    @State private var connected = false
    @State private var attempt: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Codex authorization").font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary)
            if let authorization {
                Text(authorization.userCode)
                    .font(.title2.monospaced().bold())
                    .textSelection(.enabled)
                Text("Enter this code in the Codex sign-in window.")
                    .font(.caption).foregroundStyle(.secondary)
                if let url = URL(string: authorization.verificationURL) {
                    Link("Open Codex sign-in", destination: url)
                }
            }
            HStack {
                Button(connected ? "Sign in again" : "Sign in to Codex") {
                    authorization = nil
                    attempt = UUID()
                }
                .disabled(apiClient == nil || attempt != nil)
                if attempt != nil {
                    ProgressView().controlSize(.small)
                    Button("Cancel") {
                        attempt = nil
                        authorization = nil
                        message = "Sign-in cancelled."
                    }
                }
            }
            if let settingsURL = URL(string: "https://chatgpt.com/security-settings") {
                Link("Enable device code login in ChatGPT settings", destination: settingsURL)
                    .font(.caption)
            }
        }
        .padding()
        .task {
            guard let apiClient else {
                message = "Connect to a Sloppy server to authorize Codex."
                return
            }
            do {
                let status = try await apiClient.fetchCodexAuthorizationStatus()
                guard attempt == nil else { return }
                connected = status.hasOAuthCredentials
                if connected { message = "Codex is connected on this Sloppy server." }
            } catch {
                if attempt == nil { message = error.localizedDescription }
            }
        }
        .task(id: attempt) {
            guard let attempt, let apiClient else { return }
            await signIn(attempt: attempt, apiClient: apiClient)
        }
    }

    @MainActor
    private func signIn(attempt id: UUID, apiClient: SloppyAPIClient) async {
        defer { if attempt == id { attempt = nil } }
        do {
            message = "Requesting a device code…"
            let device = try await apiClient.startCodexDeviceAuthorization()
            try Task.checkCancellation()
            guard attempt == id else { return }
            authorization = device
            message = "Waiting for Codex sign-in…"
            if let url = URL(string: device.verificationURL) { openURL(url) }
            let deadline = Date().addingTimeInterval(TimeInterval(max(1, device.expiresIn)))
            var interval = max(1, device.interval)
            while Date() < deadline {
                try await Task.sleep(for: .seconds(interval))
                let result = try await apiClient.pollCodexDeviceAuthorization(device)
                try Task.checkCancellation()
                guard attempt == id else { return }
                message = result.message
                if result.ok {
                    connected = true
                    authorization = nil
                    await onConnected()
                    return
                }
                if result.status == "slow_down" { interval += 5 }
                guard ["pending", "slow_down"].contains(result.status) else { return }
            }
            authorization = nil
            message = "The device code expired. Sign in again to get a new code."
        } catch is CancellationError {
            return
        } catch {
            if attempt == id { message = error.localizedDescription }
        }
    }
}
