import AdaEngine
import Foundation

public enum MaterialSymbol: String, CaseIterable, Sendable {
    case add = "\u{e145}"
    case arrowForward = "\u{e5c8}"
    case arrowUpward = "\u{e5d8}"
    case autoAwesome = "\u{e65f}"
    case chatAddOn = "\u{f0f3}"
    case check = "\u{e5ca}"
    case close = "\u{e5cd}"
    case collapseContent = "\u{f507}"
    case expandMore = "\u{e5cf}"
    case fiberManualRecord = "\u{e061}"
    case folder = "\u{e2c7}"
    case keyboardCommandKey = "\u{eae7}"
    case keyboardReturn = "\u{e31b}"
    case menu = "\u{e5d2}"
    case moreHoriz = "\u{e5d3}"
    case openInNew = "\u{e89e}"
    case radioButtonChecked = "\u{e837}"
    case radioButtonPartial = "\u{f560}"
    case pushPin = "\u{f10d}"
    case settings = "\u{e8b8}"
    case search = "\u{e8b6}"
    case agents = "\u{e7fb}"
    case computer = "\u{e30a}"
    case warning = "\u{e002}"
    case notification = "\u{e7f4}"
    case language = "\u{e894}"
    case branch = "\u{e0b6}"
    case schedule = "\u{e8b5}"
    case dashboard = "\u{e871}"
    case grid = "\u{e9b0}"
    case refresh = "\u{e5d5}"
    case tune = "\u{e429}"
    case layers = "\u{e53b}"
    case code = "\u{e86f}"
    case build = "\u{e869}"
    case bug = "\u{e868}"
    case astronaut = "\u{f04e}"
    case terminal = "\u{eb8e}"
    case description = "\u{e873}"
    case sidePanel = "\u{e8f3}"
    case microphone = "\u{e029}"

    var codepoint: UInt32 {
        rawValue.unicodeScalars.first?.value ?? 0
    }
}

public enum Icons {
    public static let home = IconsAtlas.image(.home)
    public static let star = IconsAtlas.image(.star)
    public static let gamedev = IconsAtlas.image(.gamedev)

    public static func materialSymbolsRounded(size: Double) -> Font {
        Font(fontResource: materialSymbolsRoundedResource, pointSize: size)
    }

    @MainActor public static func symbol(_ symbol: MaterialSymbol, size: Double) -> some View {
        Text(symbol.rawValue)
            .font(materialSymbolsRounded(size: size))
            .frame(width: Float(size), height: Float(size))
    }

    private static let materialSymbolsRoundedResource: FontResource = {
        let url = Bundle.module.url(
            forResource: "MaterialSymbolsRounded",
            withExtension: "ttf"
        ) ?? Bundle.module.url(
            forResource: "MaterialSymbolsRounded",
            withExtension: "ttf",
            subdirectory: "Fonts/MaterialSymbols"
        )

        guard let url else {
            fatalError("[Icons]: MaterialSymbolsRounded.ttf is missing from SloppyClientUI resources")
        }

        guard let resource = FontResource.custom(
            fontPath: url,
            emFontScale: 48,
            includeDefaultCharset: false,
            additionalCodepoints: MaterialSymbol.allCases.map(\.codepoint)
        ) else {
            fatalError("[Icons]: Failed to load Material Symbols Rounded font")
        }

        return resource
    }()
}
