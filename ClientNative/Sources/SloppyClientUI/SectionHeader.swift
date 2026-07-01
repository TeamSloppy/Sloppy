import Foundation
import SwiftUI

public struct SectionHeader: View {
    let title: String

    @Environment(\.theme) private var theme

    public init(_ title: String, accentColor: Color? = nil) {
        self.title = title
    }

    public var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return Text(title)
            .font(.system(size: ty.heading, weight: .semibold))
            .foregroundColor(c.textPrimary)
            .padding(.vertical, sp.xs)
    }
}
