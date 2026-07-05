import Foundation
import Testing

@Suite("Chat screen layout")
struct ChatScreenLayoutTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("phone chat layout avoids geometry reader on first render")
    func phoneChatLayoutAvoidsGeometryReaderOnFirstRender() throws {
        let source = try source("Sources", "SloppyFeatureChat", "ChatScreen.swift")

        #expect(source.contains("if idiom == .phone"))
        #expect(source.contains("chromeLayout(contentWidth: phoneContentWidth)"))
        #expect(source.contains("private var phoneContentWidth: CGFloat"))
        #expect(source.contains("screenPointWidth - rootSafeAreaInsets.leading - rootSafeAreaInsets.trailing"))
    }

    @Test("mobile composer expands to available width with dedicated circle buttons")
    func mobileComposerExpandsToAvailableWidthWithDedicatedCircleButtons() throws {
        let source = try source("Sources", "SloppyFeatureChat", "ChatComposerView.swift")

        #expect(source.contains("private struct MobileComposerCircleButton"))
        #expect(source.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        #expect(source.contains(".frame(width: ChatComposerView.phoneCircleSize, height: ChatComposerView.phoneCircleSize)"))
        #expect(source.contains(".buttonStyle(DefaultButtonStyle())"))
        #expect(source.contains(".backportGlassEffect(.regular, in: .capsule)"))
        #expect(!source.contains(".debugOverlay(.layoutBounds)"))
    }

    @Test("composer uses one compact menu for model effort and agent")
    func composerUsesOneCompactMenuForModelEffortAndAgent() throws {
        let source = try source("Sources", "SloppyFeatureChat", "ChatComposerView.swift")

        #expect(source.contains("private struct ComposerOptionsMenuView"))
        #expect(source.contains("Menu {"))
        #expect(source.contains(".menuStyle(.button)"))
        #expect(source.contains("ComposerMenuChip(title:"))
    }

    @Test("desktop transcript keeps full width scroll host with centered content column")
    func desktopTranscriptKeepsFullWidthScrollHostWithCenteredContentColumn() throws {
        let source = try source("Sources", "SloppyFeatureChat", "ChatScreen.swift")

        #expect(source.contains("ScrollView {\n                        VStack(spacing: 0) {"))
        #expect(source.contains(".frame(width: contentWidth)"))
        #expect(source.contains(".frame(maxWidth: .infinity)"))
        #expect(!source.contains(".frame(width: contentWidth)\n                .frame(maxHeight: .infinity)"))
    }

    @Test("bounded transcript uses VStack instead of LazyVStack to avoid lazy scroll layout churn")
    func boundedTranscriptUsesVStackInsteadOfLazyVStack() throws {
        let source = try source("Sources", "SloppyFeatureChat", "ChatScreen.swift")

        #expect(source.contains("VStack(alignment: .leading, spacing: theme.spacing.xl)"))
        #expect(!source.contains("LazyVStack(alignment: .leading, spacing: theme.spacing.xl)"))
    }

    @Test("tapping chat content dismisses composer focus")
    func tappingChatContentDismissesComposerFocus() throws {
        let source = try source("Sources", "SloppyFeatureChat", "ChatScreen.swift")

        #expect(source.contains(".contentShape(Rectangle())"))
        #expect(source.contains(".onTapGesture {"))
        #expect(source.contains("viewModel.dismissComposerFocus()"))
    }
}
