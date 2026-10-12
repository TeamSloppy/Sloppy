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
