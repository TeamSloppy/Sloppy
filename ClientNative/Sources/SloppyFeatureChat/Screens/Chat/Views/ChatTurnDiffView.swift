import SloppyClientCore
import SloppyClientUI
import SwiftUI

struct ChatTurnDiffView: View {
    let diff: ChatTurnDiff
    @State private var expanded = false
    @Environment(\.theme) private var theme

    var body: some View {
        let added = diff.files.reduce(0) { $0 + $1.additions }
        let removed = diff.files.reduce(0) { $0 + $1.deletions }
        DisclosureGroup(isExpanded: $expanded) {
            if expanded {
                VStack(alignment: .leading, spacing: theme.spacing.m) {
                    ForEach(diff.files) { file in
                        VStack(alignment: .leading, spacing: theme.spacing.xs) {
                            Text(verbatim: file.path).font(.caption.monospaced()).textSelection(.enabled)
                            switch file.attribution {
                            case .verified:
                                if let patch = file.patch {
                                    ScrollView([.horizontal, .vertical]) {
                                        Text(verbatim: patch)
                                            .font(.caption.monospaced())
                                            .fixedSize(horizontal: true, vertical: true)
                                            .textSelection(.enabled)
                                    }
                                    .frame(maxHeight: 220)
                                    .accessibilityLabel("File diff")
                                }
                            case .interleaved:
                                Text("The file changed outside this turn.").foregroundStyle(theme.colors.textMuted)
                            case .limited:
                                Text("This file exceeded the diff limit.").foregroundStyle(theme.colors.textMuted)
                            }
                        }
                    }
                }
                .padding(.top, theme.spacing.s)
            }
        } label: {
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                Text("Changes this turn · \(diff.files.count) files · +\(added) −\(removed)")
                    .font(.callout)
                if diff.files.contains(where: { $0.attribution == .interleaved }) {
                    Text("Some files changed outside this turn.").font(.caption)
                        .foregroundStyle(theme.colors.textMuted)
                }
                if diff.truncated {
                    Text("Some changes exceeded the diff limit.").font(.caption)
                        .foregroundStyle(theme.colors.textMuted)
                }
            }
        }
        .accessibilityIdentifier("chat-turn-diff")
    }
}
