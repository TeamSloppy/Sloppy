import SwiftUI

public enum MaterialSymbol: String, CaseIterable, Sendable {
    case add
    case arrowForward
    case arrowUpward
    case autoAwesome
    case chatAddOn
    case check
    case close
    case collapseContent
    case description
    case expandMore
    case fiberManualRecord
    case folder
    case folderOpen
    case keyboardCommandKey
    case keyboardReturn
    case menu
    case moreHoriz
    case openInNew
    case radioButtonChecked
    case radioButtonPartial
    case pushPin
    case refresh
    case settings
    case warning

    var systemName: String {
        switch self {
        case .add: "plus"
        case .arrowForward: "arrow.forward"
        case .arrowUpward: "arrow.up"
        case .autoAwesome: "sparkles"
        case .chatAddOn: "plus.message"
        case .check: "checkmark"
        case .close: "xmark"
        case .collapseContent: "rectangle.compress.vertical"
        case .description: "doc.text"
        case .expandMore: "chevron.down"
        case .fiberManualRecord: "circle.fill"
        case .folder: "folder"
        case .folderOpen: "folder.fill"
        case .keyboardCommandKey: "command"
        case .keyboardReturn: "return"
        case .menu: "line.3.horizontal"
        case .moreHoriz: "ellipsis"
        case .openInNew: "arrow.up.right.square"
        case .radioButtonChecked: "circle.inset.filled"
        case .radioButtonPartial: "circle.lefthalf.filled"
        case .pushPin: "pin.fill"
        case .refresh: "arrow.clockwise"
        case .settings: "gearshape"
        case .warning: "exclamationmark.triangle"
        }
    }
}

public enum AppIcon: Sendable {
    case home
    case star
    case gamedev

    var systemName: String {
        switch self {
        case .home: "house.fill"
        case .star: "star.fill"
        case .gamedev: "gamecontroller.fill"
        }
    }
}

public enum Icons {
    public static func image(_ icon: AppIcon) -> Image {
        Image(systemName: icon.systemName)
    }

    public static let home = image(.home)
    public static let star = image(.star)
    public static let gamedev = image(.gamedev)

    @MainActor
    public static func symbol(_ symbol: MaterialSymbol, size: Double) -> some View {
        Image(systemName: symbol.systemName)
            .font(.system(size: size))
            .symbolRenderingMode(.monochrome)
            .frame(width: size, height: size)
    }
}
