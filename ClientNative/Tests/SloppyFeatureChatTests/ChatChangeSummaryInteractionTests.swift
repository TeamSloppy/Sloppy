#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SloppyClientCore
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyFeatureChat

@Suite("Chat change summary interaction", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct ChatChangeSummaryInteractionTests {
    @Test func cleanTreeIsHiddenAndChangedTreeOpensReview() async throws {
        AppKitTestAccessibility.enable()
        var opened: ProjectWorkingTreeSourceControlResponse?
        func summary(_ sourceControl: ProjectWorkingTreeSourceControlResponse) -> AnyView {
            AnyView(ChatChangeSummaryView(sourceControl: sourceControl)
                .environment(\.workingTreeReviewHandler, { sourceControl, _, _ in opened = sourceControl })
                .theme(.sloppyDark))
        }
        let clean = ProjectWorkingTreeSourceControlResponse(providerId: "git", isRepository: true)
        let host = NSHostingView(rootView: summary(clean))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(150))
        #expect(AppKitTestAccessibility.element(in: host, identifier: "chat.change-summary") == nil)
        // File metadata changes can have zero changed lines and still need review.
        let changed = ProjectWorkingTreeSourceControlResponse(
            providerId: "git", isRepository: true,
            diff: "diff --git a/tool.sh b/tool.sh\nold mode 100644\nnew mode 100755\n"
        )
        #expect(changed.hasChanges)
        host.rootView = summary(changed)
        try await Task.sleep(for: .milliseconds(150))
        let button = try #require(AppKitTestAccessibility.element(in: host, identifier: "chat.change-summary"))
        #expect(AppKitTestAccessibility.press(button))
        #expect(opened == changed)
    }
}
#endif
