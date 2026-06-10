import AdaEngine
import SloppyClientUI

@MainActor
struct SloppyGlassShell<Content: View>: View {
    private static var cornerRadius: Float { 28 }

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangleShape(cornerRadius: Self.cornerRadius)

        return content
            .background {
                shape.fill(Theme.sloppyDark.colors.background)
            }
            .glassEffect(.regular.tint(Color.white.opacity(0.035 as Float)), in: shape)
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.18 as Float),
                        Color.white.opacity(0.04 as Float),
                        Color.black.opacity(0.20 as Float),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .allowsHitTesting(false)
            }
            .overlay {
                RectangleShape()
                    .fill(Color.white)
                    .shaderEffect(SloppyShaderEffects.edgeGlow, placement: .overlay)
                    .allowsHitTesting(false)
            }
            .mask(shape)
            .overlay {
                shape
                    .stroke(Theme.sloppyDark.colors.border.opacity(0.72 as Float), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}
