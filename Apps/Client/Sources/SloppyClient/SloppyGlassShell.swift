import AdaEngine
import SloppyClientUI

@MainActor
struct SloppyGlassShell<Content: View>: View {
    let cornerRadius: Float
    let content: Content

    @Environment(\.theme) private var theme

    init(cornerRadius: Float = 34, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        let c = theme.colors
        let shellShape = RoundedRectangleShape(cornerRadius: cornerRadius)

        return ZStack {
            LinearGradient(
                stops: [
                    Gradient.Stop(color: Color.black.opacity(0.84 as Float), location: 0),
                    Gradient.Stop(color: Color.black.opacity(0.64 as Float), location: 0.42),
                    Gradient.Stop(color: Color.black.opacity(0.22 as Float), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            .ignoresSafeArea()
//
//            LinearGradient(
//                stops: [
//                    Gradient.Stop(color: Color.white.opacity(0.065 as Float), location: 0),
//                    Gradient.Stop(color: Color.white.opacity(0.018 as Float), location: 0.30),
//                    Gradient.Stop(color: Color.clear, location: 1),
//                ],
//                startPoint: .topLeading,
//                endPoint: .bottomTrailing
//            )
//            .allowsHitTesting(false)
//            
            content
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }
}
