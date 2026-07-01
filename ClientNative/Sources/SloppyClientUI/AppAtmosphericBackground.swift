import SwiftUI
import Foundation

public struct AppAtmosphericBackground: View {
    @Environment(\.theme) private var theme
    
    public init() {}
    
    public var body: some View {
        let c = theme.colors
        
        LinearGradient(
            stops: [
                Gradient.Stop(color: c.background, location: 0),
                Gradient.Stop(color: c.background, location: 0.5),
                Gradient.Stop(color: c.background.opacity(0.1 as Float), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .background(.thinMaterial)
        .allowsHitTesting(false)
    }
}

struct BlurEffectView: View {

}

#if os(macOS)
extension BlurEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {

    }
}
#else
extension BlurEffectView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView()
        view.material = .material
        return view
    }

    func updateUIView(_ nsView: UIVisualEffectView, context: Context) {

    }
}
#endif

#Preview {
    AppAtmosphericBackground()
        .background(
            Color.red
        )
}
