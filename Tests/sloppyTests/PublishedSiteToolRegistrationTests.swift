import Testing
@testable import sloppy

@Test("published site tools are registered")
func publishedSiteToolsRegistered() {
    let tools = ToolRegistry.makeDefault().knownToolIDs
    #expect(tools.contains("sites.list"))
    #expect(tools.contains("sites.publish"))
    #expect(tools.contains("sites.update"))
    #expect(tools.contains("sites.delete"))
}

@Test("site publishing skill is bundled with site tools")
func sitePublishingSkillBundled() throws {
    let skill = try #require(
        BuiltInSkillCatalog.all().first { $0.repo == "site-publishing" }
    )
    #expect(skill.userInvocable)
    #expect(skill.allowedTools.contains("sites.publish"))
    #expect(skill.allowedTools.contains("sites.delete"))
}
