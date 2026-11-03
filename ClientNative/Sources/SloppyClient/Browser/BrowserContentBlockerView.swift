import SwiftUI

@MainActor
struct BrowserContentBlockerView: View {
    let blocker: BrowserContentBlocker
    var pageURL: URL?
    var onReload: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Block ads", isOn: Binding(get: { blocker.isEnabled }, set: { enabled in
                        Task { await blocker.setEnabled(enabled); onReload() }
                    }))
                    .accessibilityIdentifier("browser-block-ads")
                    if let pageURL, let host = BrowserContentBlocker.host(for: pageURL) {
                        Toggle("Block ads on \(host)", isOn: Binding(get: { blocker.isSiteEnabled(pageURL) }, set: { enabled in
                            Task { await blocker.setSiteEnabled(enabled, for: pageURL); onReload() }
                        }))
                        .disabled(!blocker.isEnabled || blocker.isApplying)
                        .accessibilityIdentifier("browser-block-ads-on-site")
                    }
                    Text(status).font(.caption).foregroundStyle(.secondary)
                } header: { Text("Protection") } footer: {
                    Text("Applies to pages in Sloppy. Site exceptions include subdomains. Reload other open pages to fully apply changes.")
                }
                Section("Filter lists") {
                    LabeledContent("List", value: "EasyList")
                    if blocker.ruleCount > 0 {
                        LabeledContent("Rules", value: blocker.ruleCount.formatted())
                    }
                    if let date = blocker.lastCheckedAt {
                        LabeledContent("Last checked", value: date.formatted(date: .abbreviated, time: .shortened))
                    } else {
                        Text("Using the list included with Sloppy").font(.callout).foregroundStyle(.secondary)
                    }
                    Toggle("Update automatically", isOn: Binding(get: { blocker.automaticUpdates }, set: { blocker.setAutomaticUpdates($0) }))
                        .accessibilityIdentifier("browser-filter-auto-update")
                    Button {
                        Task { await blocker.update() }
                    } label: {
                        HStack {
                            Text(blocker.isUpdating ? "Updating…" : "Check for updates")
                            if blocker.isUpdating { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(blocker.isUpdating || blocker.isApplying)
                    .accessibilityIdentifier("browser-filter-update")
                    if let error = blocker.lastError {
                        Text(error).foregroundStyle(.red).font(.callout)
                        Text(blocker.isReady ? "Your previous filter list is still available." : "Protection is unavailable. Try updating the list.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    if blocker.disabledSites.isEmpty {
                        Text("No site exceptions").foregroundStyle(.secondary)
                    }
                    ForEach(blocker.disabledSites, id: \.self) { host in
                        HStack {
                            Text(host).textSelection(.enabled)
                            Spacer()
                            Button("Remove") {
                                Task { await blocker.removeException(host); onReload() }
                            }
                            .disabled(blocker.isApplying)
                            .accessibilityLabel("Remove exception for \(host)")
                        }
                    }
                } header: { Text("Sites with blocking disabled") }
                Section {
                    Link("The EasyList authors", destination: URL(string: "https://easylist.to/")!)
                    Link("Filter licence · CC BY-SA 3.0", destination: URL(string: "https://easylist.to/pages/licence.html")!)
                    Text("Checks daily while you use the browser. Downloads contain filter rules; browsing history is not sent with update requests.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Ad Blocking")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task { await blocker.prepare() }
#if os(macOS)
        .frame(width: 560, height: 660)
#else
        .presentationDetents([.large])
#endif
    }

    private var status: String {
        if !blocker.isEnabled { return "Ad blocking is off." }
        if blocker.isApplying { return "Preparing filter rules…" }
        if !blocker.isReady { return "Preparing ad blocking…" }
        if !blocker.isSiteEnabled(pageURL) { return "Ad blocking is off for this site." }
        return "Ad blocking is on."
    }
}

#if os(macOS)
@MainActor
struct BrowserContentBlockerButton: View {
    let state: BrowserWorkspaceState
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            Image(systemName: state.contentBlocker.isEnabled && state.contentBlocker.isSiteEnabled(state.selectedTab?.url)
                  ? "shield.lefthalf.filled" : "shield.slash")
                .frame(width: 24, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Ad Blocking")
        .accessibilityLabel("Ad Blocking")
        .accessibilityIdentifier("browser-ad-blocking")
        .sheet(isPresented: $isPresented) {
            let page = state.selectedPage
            BrowserContentBlockerView(blocker: state.contentBlocker, pageURL: state.selectedTab?.url,
                                      onReload: { page?.reload() })
        }
    }
}
#endif
