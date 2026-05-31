import Testing
@testable import sloppy
@testable import Protocols

@Test
func projectAutopilotPlannerDecodesStrictSubtaskGraph() throws {
    let json = """
    {
      "subtasks": [
        {
          "id": "design",
          "title": "Design API",
          "description": "Define payloads",
          "kind": "planning",
          "tags": ["autopilot"],
          "dependsOn": [],
          "verificationHints": ["Review schema"]
        },
        {
          "id": "build",
          "title": "Build API",
          "description": "Implement endpoint",
          "kind": "execution",
          "tags": ["autopilot"],
          "dependsOn": ["design"],
          "verificationHints": ["Run tests"]
        }
      ]
    }
    """

    let planned = try ProjectAutopilotPlanner.decode(json)

    #expect(planned.count == 2)
    #expect(planned[0].temporaryID == "design")
    #expect(planned[0].kind == .planning)
    #expect(planned[1].dependsOnTemporaryIds == ["design"])
}

@Test
func projectAutopilotPlannerRejectsUnknownDependencies() throws {
    let json = """
    {
      "subtasks": [
        {
          "id": "build",
          "title": "Build API",
          "description": "Implement endpoint",
          "dependsOn": ["missing"]
        }
      ]
    }
    """

    #expect(throws: ProjectAutopilotPlanner.PlannerError.self) {
        _ = try ProjectAutopilotPlanner.decode(json)
    }
}
