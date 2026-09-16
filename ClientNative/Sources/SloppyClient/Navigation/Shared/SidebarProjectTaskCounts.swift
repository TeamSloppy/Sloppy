import SwiftUI
import SloppyClientCore
import SloppyClientUI

struct SidebarProjectTaskCounts: View {
    let project: APIProjectRecord
    @Environment(\.theme) private var theme

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { total; inProgress }
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 5) { total; inProgress }
        }
        .font(.system(size: theme.typography.caption))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sidebar.project.\(project.storageID).task-counts")
    }

    private var total: some View {
        Label("\(project.tasks.map { String($0.count) } ?? "—") tasks", systemImage: "checklist")
            .foregroundStyle(theme.colors.textMuted)
    }

    private var inProgress: some View {
        Label("\(project.inProgressTaskCount.map(String.init) ?? "—") in progress", systemImage: "arrow.trianglehead.2.clockwise")
            .foregroundStyle((project.inProgressTaskCount ?? 0) > 0 ? theme.colors.statusActive : theme.colors.textMuted)
    }
}
