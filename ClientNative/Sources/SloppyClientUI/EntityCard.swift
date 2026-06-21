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
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography
        let accent = accentColor ?? c.accent

        return HStack(spacing: 0) {
            Color.clear
                .frame(width: bo.thick)
                .background(accent)
                .opacity(0.92 as Float)

            HStack(spacing: sp.m) {
                VStack(alignment: .leading, spacing: sp.xs) {
                    Text(title.uppercased())
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
                        .glassEffect(.regular.tint(accent.opacity(0.08 as Float)), in: .rect(cornerRadius: 10))
                }
            }
            .padding(sp.m)
        }
        .glassEffect(.regular.tint(c.surfaceGlow.opacity(0.16 as Float)), in: .rect(cornerRadius: 20))
        .border(c.border.opacity(0.72 as Float), lineWidth: bo.thin)
    }
}
