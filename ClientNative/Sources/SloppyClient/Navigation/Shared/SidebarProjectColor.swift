import SloppyClientCore
import SwiftUI

enum SidebarProjectColor: String, CaseIterable {
    case red, orange, yellow, green, blue, purple, pink

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        }
    }
}

extension ClientSettings {
    func sidebarColor(for project: APIProjectRecord) -> Color? {
        projectColors[project.storageID].flatMap(SidebarProjectColor.init(rawValue:))?.color
    }
}
