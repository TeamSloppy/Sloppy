import Testing
@testable import sloppy

@Test
func deepResearchParserParsesSlashCommandWithOptions() throws {
    let request = try DeepResearchCommandParser.parseSlashCommand(
        "/deepresearch --mode compare --rounds 4 Compare GPT-5 and Claude for code review"
    )

    #expect(request.mode == .compare)
    #expect(request.rounds == 4)
    #expect(request.prompt == "Compare GPT-5 and Claude for code review")
}

@Test
func deepResearchParserUsesDefaultsForSlashCommand() throws {
    let request = try DeepResearchCommandParser.parseSlashCommand("/deepresearch map current AI search tools")

    #expect(request.mode == .explore)
    #expect(request.rounds == 3)
    #expect(request.prompt == "map current AI search tools")
}

@Test
func deepResearchParserRejectsInvalidMode() {
    #expect(throws: DeepResearchCommandParser.ValidationError.invalidMode("audit")) {
        try DeepResearchCommandParser.parseArguments(["--mode", "audit", "Review this"])
    }
}

@Test
func deepResearchParserRejectsOutOfRangeRounds() {
    #expect(throws: DeepResearchCommandParser.ValidationError.invalidRounds(9)) {
        try DeepResearchCommandParser.parseArguments(["--rounds", "9", "Review this"])
    }
}

@Test
func deepResearchParserBuildsSkillInvocation() throws {
    let request = try DeepResearchCommandParser.parseArguments([
        "--mode", "review",
        "--rounds", "2",
        "Review Sloppy search architecture"
    ])

    let message = DeepResearchCommandParser.skillInvocationMessage(for: request)

    #expect(message.contains("Use installed skill `sloppy/deep-research`"))
    #expect(message.contains("mode: review"))
    #expect(message.contains("rounds: 2"))
    #expect(message.contains("Review Sloppy search architecture"))
}
