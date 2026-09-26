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

struct SidebarColorMenuOption: View {
    let title: String
    let color: SidebarProjectColor?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let color {
                Circle()
                    .fill(color.color)
                    .frame(width: 12, height: 12)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(color == .yellow ? .black : .white)
                        }
                    }
            } else {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle.slash")
                    .foregroundStyle(.secondary)
            }

            Text(title)
        }
    }
}

extension ClientSettings {
    func sidebarColor(for project: APIProjectRecord) -> Color? {
        projectColors[project.storageID].flatMap(SidebarProjectColor.init(rawValue:))?.color
    }

    func sidebarColor(for session: ChatSessionSummary) -> Color? {
        sidebarChatColor(for: session)?.color
    }

    func sidebarChatColor(for session: ChatSessionSummary) -> SidebarProjectColor? {
        chatColors[session.storageID].flatMap(SidebarProjectColor.init(rawValue:))
    }
}
