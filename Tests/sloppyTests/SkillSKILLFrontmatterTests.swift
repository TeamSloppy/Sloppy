import Foundation
import Testing
@testable import sloppy

@Suite("Skill SKILL.md frontmatter")
struct SkillSKILLFrontmatterTests {
    @Test("Parses model from YAML frontmatter")
    func parsesModel() {
        let md = """
        ---
        name: test-skill
        model: openai:gpt-5.4-mini
        ---

        # Body
        """
        #expect(SkillSKILLFrontmatter.preferredModel(fromMarkdown: md) == "openai:gpt-5.4-mini")
    }

    @Test("Returns nil without frontmatter")
    func noFrontmatter() {
        #expect(SkillSKILLFrontmatter.preferredModel(fromMarkdown: "# Title") == nil)
    }
}
