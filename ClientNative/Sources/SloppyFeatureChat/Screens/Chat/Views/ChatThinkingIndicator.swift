import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI
import Textual

struct ChatThinkingIndicator: View {
    let label: String
    let details: String?

    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            ChatShimmerText(text: label)
                .font(.system(size: theme.typography.body, weight: .medium))
            Spacer(minLength: 0)
        }
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let details, !details.isEmpty else { return label }
        return "\(label). \(details)"
    }
}

struct ChatShimmerText: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme

    var body: some View {
        if reduceMotion {
            Text(text)
                .foregroundStyle(theme.colors.textSecondary)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let progress = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.8) / 1.8
                let center = -0.35 + progress * 1.7

                Text(text)
                    .foregroundStyle(theme.colors.textMuted)
                    .overlay {
                        GeometryReader { geometry in
                            LinearGradient(
                                colors: [
                                    theme.colors.textPrimary.opacity(0 as Double),
                                    theme.colors.textPrimary,
                                    theme.colors.textPrimary.opacity(0 as Double),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: geometry.size.width * 0.7)
                            .offset(x: geometry.size.width * (center - 0.35))
                        }
                        .mask(Text(text))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
            }
        }
    }
}
