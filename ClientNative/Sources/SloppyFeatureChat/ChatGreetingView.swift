import Foundation
import SwiftUI
import SloppyClientUI

public struct ChatGreetingView: View {
    public let agentName: String

    public init(agentName: String) {
        self.agentName = agentName
    }

    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme

    public var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography
        let isPhone = idiom == .phone

        return VStack(alignment: .center, spacing: sp.s) {
            Text("Hi Camille,\nwhat can I help with?")
                .font(.system(size: isPhone ? ty.title : ty.hero))
                .foregroundColor(c.textPrimary)
                .multilineTextAligment(.center)
                .lineLimit(isPhone ? 3 : 2)
                .frame(minWidth: 0, maxWidth: .infinity)
        }
        .padding(.horizontal, isPhone ? sp.s : sp.m)
    }
}
