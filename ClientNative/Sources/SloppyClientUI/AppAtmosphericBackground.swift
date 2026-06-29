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
                Gradient.Stop(color: c.background.opacity(0.08 as Float), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }
}

