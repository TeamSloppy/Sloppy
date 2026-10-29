import Foundation
import AdaEngine

/// A slowly evolving glyph field. TimelineView stops with the greeting's view lifecycle.
public struct WorkspaceAtmosphere: View {
    @Environment(\.theme) private var theme
    public init() {}
    public var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 0.16)) { timeline in
            Text(Self.frame(at: timeline.date.timeIntervalSinceReferenceDate))
                .font(Font(fontResource: Self.font, pointSize: Double(max(8, geometry.size.width / 110))))
                .foregroundColor(theme.colors.textMuted.opacity(0.15 as Float))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }.allowsHitTesting(false)
    }
    private static func frame(at time: Double) -> String {
        let glyphs: [Character] = Array(".:-=+*")
        var result: [Character] = []
        result.reserveCapacity(field.count)
        for (index, character) in field.enumerated() {
            guard let rank = glyphs.firstIndex(of: character) else { result.append(character); continue }
            let horizontal: Double = Double(index % 110) * 0.11 + time * 0.4
            let vertical: Double = Double(index / 110) * 0.22 - time * 0.3
            let wave: Double = Foundation.sin(horizontal) + Foundation.cos(vertical)
            let shift: Int = wave > 0.8 ? 1 : (wave < -0.8 ? -1 : 0)
            result.append(glyphs[Swift.max(0, Swift.min(glyphs.count - 1, rank + shift))])
        }
        return String(result)
    }
    private static let field: String = {
        guard let url = Bundle.module.url(forResource: "WorkspaceAtmosphere", withExtension: "txt") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()
    private static let font: FontResource = {
        #if os(Windows)
        let root = ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:/Windows"
        let path = URL(fileURLWithPath: root).appendingPathComponent("Fonts/consola.ttf")
        #else
        let path = URL(fileURLWithPath: "/System/Library/Fonts/Menlo.ttc")
        #endif
        return FontResource.custom(fontPath: path, includeDefaultCharset: false,
            additionalCodepoints: Array(" .:-=+*\n".unicodeScalars.map(\.value))) ?? .system()
    }()
}
