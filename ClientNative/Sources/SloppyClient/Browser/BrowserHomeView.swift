import SwiftUI
import SloppyClientUI
import SloppyFeatureChat

@MainActor
struct BrowserHomeView: View {
    let state: BrowserWorkspaceState
    let onAskAgent: (String) -> Void
    var showsComposer = true
    var onComposerDismissed: () -> Void = {}
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                theme.colors.background
                ChatASCIIBackground(protectedWidth: min(600, geometry.size.width))
                ScrollView {
                    VStack(spacing: 28) {
                        Text("Where to next?")
                            .font(.system(size: 36, weight: .semibold))
                            .multilineTextAlignment(.center)
                        if showsComposer {
                            BrowserHomeComposer(onStartChat: onAskAgent)
                                .transition(.identity)
                                .onDisappear(perform: onComposerDismissed)
                        }
                        frequentSites
                    }
                    .padding(28)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
            }
        }
        .accessibilityIdentifier("browser-home")
    }

    private var frequentSites: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Frequently visited").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
            if state.history.frequentSites().isEmpty {
                Text("Your frequently visited sites will appear here.")
                    .font(.callout).foregroundStyle(.secondary).padding(12)
            } else {
                ForEach(state.history.frequentSites()) { site in
                    Button { state.open(site.url, inNewTab: true) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "globe").font(.system(size: 16)).frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(site.id).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                if site.title != site.id {
                                    Text(site.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 12)
                            Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("browser-frequent-site-\(site.id)")
                }
            }
        }
    }
}
