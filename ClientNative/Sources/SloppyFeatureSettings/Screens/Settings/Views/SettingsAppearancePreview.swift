import SwiftUI

/// A miniature window illustrating the preference; its colors intentionally preview each mode.
struct SettingsAppearancePreview: View {
    let isDark: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 3) {
                    ForEach(0..<3) { _ in
                        Circle().fill(ink.opacity(0.25)).frame(width: 4, height: 4)
                    }
                }
                .padding(.bottom, 3)
                RoundedRectangle(cornerRadius: 2).fill(accent).frame(height: 6)
                RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.12)).frame(height: 4)
                RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.12)).frame(width: 20, height: 4)
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(width: 52)
            .background(ink.opacity(0.04))
            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.55)).frame(width: 38, height: 5)
                RoundedRectangle(cornerRadius: 3).fill(ink.opacity(0.08)).frame(height: 16)
                RoundedRectangle(cornerRadius: 3).fill(ink.opacity(0.08)).frame(height: 10)
                Spacer(minLength: 0)
            }
            .padding(10)
        }
        .background(isDark ? Color(white: 0.12) : Color(white: 0.98))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6).strokeBorder(ink.opacity(0.12), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private var ink: Color { isDark ? .white : .black }
}
