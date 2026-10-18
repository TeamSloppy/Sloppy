import Foundation
import SwiftUI

public struct EntityCard: View {
    let title: String
    let subtitle: String
    let trailing: String?
    let accentColor: Color?
    let onTap: (() -> Void)?

    @Environment(\.theme) private var theme

    public init(
        title: String,
        subtitle: String,
        trailing: String? = nil,
        accentColor: Color? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.accentColor = accentColor
        self.onTap = onTap
    }

    public var body: some View {
        if let onTap {
            Button(action: onTap) {
                cardContent
            }
#if os(macOS)
            .buttonStyle(.plain)
#endif
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography
        let accent = accentColor ?? c.accent

        return HStack(spacing: 0) {
            HStack(spacing: sp.m) {
                VStack(alignment: .leading, spacing: sp.xs) {
                    Text(displayTitle)
                        .font(.system(size: ty.body))
                        .foregroundColor(c.textPrimary)
                    Text(subtitle)
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.textSecondary)
                }
                Spacer()
                if let trailing {
                    Text(trailing.uppercased())
                        .font(.system(size: ty.micro))
                        .foregroundColor(accent)
                        .padding(.horizontal, sp.s)
                        .padding(.vertical, sp.xs)
                        .background(accent.opacity(0.10 as Float))
                }
            }
            .padding(sp.m)
        }
#if os(macOS)
        .frame(minHeight: 72)
#else
        .frame(idealHeight: 56, maxHeight: 75)
#endif
        .desktopPanel()
    }

    private var displayTitle: String {
#if os(macOS)
        title
#else
        title.uppercased()
#endif
    }
}

#Preview {
    EntityCard(title: "Agent", subtitle: "Sloppy", trailing: "AAA?", accentColor: .red, onTap: nil)
}
