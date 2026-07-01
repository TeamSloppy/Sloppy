import SwiftUI
import SloppyClientUI

@MainActor
struct SloppyGlassShell<Content: View>: View {
    private static var cornerRadius: CGFloat { 28 }

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius)

        return content
            .background {
                shape.fill(Theme.sloppyDark.colors.background)
            }
            .background(.ultraThinMaterial, in: shape)
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.18),
                        Color.white.opacity(0.04),
                        Color.black.opacity(0.20),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .allowsHitTesting(false)
            }
            .mask(shape)
            .overlay {
                shape
                    .stroke(Theme.sloppyDark.colors.border.opacity(0.72), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

#Preview {
    SloppyGlassShell {
        Text("Some loooong text")
            .padding(.all, 32)
    }
    .padding(.all, 32)
}
