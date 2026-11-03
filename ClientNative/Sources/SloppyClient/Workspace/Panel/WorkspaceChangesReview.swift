import SwiftUI
import SloppyClientCore
import SloppyFeatureChat

/// Presents the exact working-tree snapshot selected in the chat or workspace inspector.
struct WorkspaceChangesReviewPresenter: ViewModifier {
    private struct Selection: Identifiable {
        let id = UUID()
        let sourceControl: ProjectWorkingTreeSourceControlResponse
        let title: String?
        let path: String?
    }

    @State private var selection: Selection?

    func body(content: Content) -> some View {
        content
            .environment(\.workingTreeReviewHandler, { sourceControl, title, path in
                selection = Selection(sourceControl: sourceControl, title: title, path: path)
            })
            .sheet(item: $selection) { selection in
                WorkspaceChangesReviewView(sourceControl: selection.sourceControl,
                                           title: selection.title, highlightedPath: selection.path)
            }
    }
}

struct WorkspaceChangesReviewView: View {
    let sourceControl: ProjectWorkingTreeSourceControlResponse
    var title: String?
    var highlightedPath: String?

    @State private var layout = CodeReviewDiffLayout.oneSide
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let message = sourceControl.message {
                    Text(message).font(.callout).padding()
                }
                if sourceControl.diffTruncated {
                    Text("This diff is truncated. Some changes are not shown.")
                        .font(.callout).foregroundStyle(.secondary).padding()
                }
                CodeReviewSideBySideDiffView(diff: sourceControl.diff, layout: layout,
                                            highlightedPath: highlightedPath)
            }
            .navigationTitle(title.map { "Review · \($0)" } ?? "Review changes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("workspace.changes.review.done")
                }
                ToolbarItem(placement: .automatic) {
                    Picker("Diff layout", selection: $layout) {
                        ForEach(CodeReviewDiffLayout.allCases) { layout in
                            Text(layout.title).tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 700, idealWidth: 1000, minHeight: 480, idealHeight: 700)
#endif
        .accessibilityIdentifier("workspace.changes.review")
    }
}
