import Foundation
import Testing
import SloppyClientCore
@testable import SloppyClient

@Suite("Workspace document preview", .serialized)
@MainActor
struct WorkspaceDocumentPreviewTests {
    @Test func recognizesDocumentsAndDefaultsToPreview() {
        let fixture = SourceFileFixture()
        for path in ["guide.md", "GUIDE.MD", "guide.markdown", "guide.mdown", "page.html", "PAGE.HTM"] {
            let model = WorkspaceSourceFileViewModel(reference: .init(path: path), apiClient: fixture.api, scope: .project("p"))
            #expect(model.documentKind != nil)
            #expect(model.displayMode == .preview)
        }
        let code = WorkspaceSourceFileViewModel(reference: .init(path: "File.swift"), apiClient: fixture.api, scope: .project("p"))
        #expect(code.documentKind == nil)
        #expect(code.displayMode == .raw)
    }

    @Test func switchingAndReloadPreserveSourceAndModeWithoutExtraFetch() async {
        let source = "# Heading\n\n**Bold** and `code`.\n"
        let fixture = SourceFileFixture(content: source)
        let model = WorkspaceSourceFileViewModel(reference: .init(path: "guide.md"), apiClient: fixture.api, scope: .project("p"))
        await model.loadIfNeeded()
        model.displayMode = .raw
        await model.loadIfNeeded()
        #expect(model.content?.content == source)
        #expect(fixture.requests.count == 1)
        model.reload()
        await model.loadIfNeeded()
        #expect(model.displayMode == .raw)
        #expect(model.content?.content == source)
        #expect(fixture.requests.count == 2)
        model.displayMode = .preview
        #expect(model.lines.first == "# Heading")
    }

    @Test func explicitLineReferencesOpenRawAndNavigateExistingPreview() {
        let fixture = SourceFileFixture()
        let model = WorkspaceSourceFileViewModel(reference: .init(path: "guide.md", line: 3), apiClient: fixture.api, scope: .project("p"))
        #expect(model.displayMode == .raw)
        model.displayMode = .preview
        model.navigate(to: .init(path: "guide.md", line: 5))
        #expect(model.displayMode == .raw)
        #expect(model.reference.line == 5)
        model.displayMode = .preview
        model.navigate(to: .init(path: "guide.md"))
        #expect(model.displayMode == .preview)
    }

    @Test func htmlPolicyRejectsActiveResourcesAndNonWebLinks() throws {
        let source = "<html><head><script>alert(1)</script></head><body>Document</body></html>"
        let document = HTMLPreviewPolicy.document(source)
        #expect(document.contains("default-src 'none'"))
        #expect(document.contains("script-src 'none'"))
        #expect(document.contains("form-action 'none'"))
        #expect(document.contains("base-uri 'none'"))
        let policyRange = try #require(document.range(of: "Content-Security-Policy"))
        let sourceRange = try #require(document.range(of: source))
        #expect(policyRange.lowerBound < sourceRange.lowerBound)
        for text in ["file:///etc/passwd", "javascript:alert(1)", "data:text/html,Hello", "sloppy://settings"] {
            let url = try #require(URL(string: text))
            #expect(!HTMLPreviewPolicy.isExternalLink(url))
            #expect(!HTMLPreviewPolicy.isInternalNavigation(url))
        }
        #expect(HTMLPreviewPolicy.isExternalLink(try #require(URL(string: "https://example.com"))))
        #expect(HTMLPreviewPolicy.isInternalNavigation(try #require(URL(string: "about:blank#heading"))))
    }
}
