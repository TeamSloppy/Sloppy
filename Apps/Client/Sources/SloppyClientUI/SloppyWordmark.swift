import AdaEngine
import Foundation

#if canImport(CoreText)
import CoreText
#endif

public struct SloppyWordmark: View {
    public let size: Double
    @Environment(\.theme) private var theme

    public init(size: Double = 29) { self.size = size }

    public var body: some View {
        Text(lettering)
            .lineLimit(1)
            .accessibilityIdentifier("sloppy.wordmark")
    }

    private var lettering: AttributedText {
        var word = AttributedText("sloppy")
        word.font = Font(fontResource: Self.wordmarkFont, pointSize: size)
        word.foregroundColor = theme.colors.textPrimary
        word.kern = Float(-1.2 * size / 29)
        var period = AttributedText(".")
        period.font = word.font
        period.kern = word.kern
        period.foregroundColor = theme.colors.textPrimary
        word.append(period)
        return word
    }

    // AdaUI's bundled default is Open Sans. Resolve the platform font for the approved wordmark.
    private static let wordmarkFont: FontResource = {
        var candidates: [URL] = []
        #if canImport(CoreText)
        if let font = CTFontCreateUIFontForLanguage(.system, 29, nil),
           let url = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL {
            candidates.append(url)
        }
        #elseif os(Windows)
        let windows = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:/Windows")
        candidates = ["SegoeUIVF.ttf", "segoeuib.ttf"].map { windows.appendingPathComponent("Fonts/\($0)") }
        #endif
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let font = FontResource.custom(fontPath: url, includeDefaultCharset: false,
                                              additionalCodepoints: Array("sloppy.".unicodeScalars.map(\.value)),
                                              variations: [.weight(750)]) {
                return font
            }
        }
        return .system(weight: .heavy)
    }()
}
