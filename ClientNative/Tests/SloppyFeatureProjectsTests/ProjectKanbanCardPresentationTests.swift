import Foundation
import Testing

@Suite("Kanban card presentation")
struct ProjectKanbanCardPresentationTests {
    @Test("cards provide a visible hover state")
    func cardsProvideVisibleHoverState() throws {
        let source = try sourceFile("Sources/SloppyFeatureProjects/Screens/Projects/Kanban/ProjectKanbanCardContent.swift")

        #expect(source.contains("@State private var isHovered = false"))
        #expect(source.contains(".onHover { isHovered = $0 }"))
        #expect(source.contains(".scaleEffect(isHovered ? 1.01 : 1)"))
        #expect(source.contains(".stroke(isHovered ? theme.colors.accent.opacity(0.65) : theme.colors.border"))
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
