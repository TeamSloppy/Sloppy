import SwiftUI

public extension Color {
    static func fromHex(_ hex: UInt32, alpha: Double = 1) -> Color {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        return Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    init(_ red: Float, _ green: Float, _ blue: Float, _ alpha: Float) {
        self.init(red: Double(red), green: Double(green), blue: Double(blue), opacity: Double(alpha))
    }

    func opacity(_ value: Float) -> Color {
        opacity(Double(value))
    }
}
