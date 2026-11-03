import SwiftUI
import WebKit

@MainActor
struct BrowserSiteDataSection: View {
    let url: URL
    let page: WorkspaceWebViewModel?
    let onClear: () -> Void
    @State private var data: BrowserSiteData?
    @State private var confirmsRemoval = false

    var body: some View {
        Section("Website data") {
            if let data {
                if data.isBusy { ProgressView().controlSize(.small) }
                if data.hasLoaded {
                    if data.records.isEmpty {
                        Text("No stored data for this site.").foregroundStyle(.secondary)
                    } else {
                        Text("WebKit stores data for \(data.recordNames) together, including subdomains and ports.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Clear cached files") {
                    Task { if await data.clear(includingCookiesAndStorage: false) { onClear() } }
                }
                .disabled(data.isBusy || data.records.isEmpty)
                .accessibilityIdentifier("browser-site-clear-cache")
                Button("Remove cookies and site storage…", role: .destructive) { confirmsRemoval = true }
                    .disabled(data.isBusy || data.records.isEmpty)
                    .accessibilityIdentifier("browser-site-clear-data")
                if let status = data.status { Text(status).font(.caption).foregroundStyle(.secondary) }
            } else { ProgressView().controlSize(.small) }
        }
        .task(id: BrowserSiteOrigin(url)?.id) {
            guard let origin = BrowserSiteOrigin(url) else { return }
            let state = BrowserSiteData(origin: origin, dataStore: page?.nativeWebView?.configuration.websiteDataStore ?? .default())
            data = state
            await state.inspect()
        }
        .confirmationDialog("Remove cookies and site storage?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("Remove site data", role: .destructive) {
                if let data { Task { if await data.clear(includingCookiesAndStorage: true) { onClear() } } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes data for \(data?.recordNames ?? url.host ?? "this site"), including its subdomains and ports, and signs you out of that site.")
        }
    }
}
