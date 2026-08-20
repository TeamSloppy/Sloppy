import Foundation
import Testing
@testable import SloppyClientCore

@Test
func startrekTaskMetadataDecodesAdditively() throws {
    let data = Data(#"""
    {
      "id":"task-1",
      "title":"Synced",
      "status":"in_progress",
      "externalMetadata":{
        "providerId":"startrek",
        "externalIssueKey":"TEST-42",
        "externalIssueURL":"https://st.yandex-team.ru/TEST-42",
        "externalStatus":{"key":"inProgress","display":"В работе","type":"inProgress"},
        "externalAssignee":"User",
        "externalPriority":"Критичный",
        "externalVersion":7,
        "origin":"startrek",
        "syncState":"synced"
      }
    }
    """#.utf8)

    let task = try JSONDecoder().decode(APIProjectTask.self, from: data)
    #expect(task.externalMetadata?.externalIssueKey == "TEST-42")
    #expect(task.externalMetadata?.externalStatus?.display == "В работе")
    #expect(task.externalMetadata?.externalVersion == 7)
}

@Test
func legacyTaskSyncSettingsDecodeWithoutSource() throws {
    let data = Data(#"""
    {
      "enabled":true,
      "providerId":"github",
      "statusMappings":{},
      "inboundStatusMappings":{},
      "syncSchedule":{"enabled":true,"intervalMinutes":15},
      "health":{"status":"ok"}
    }
    """#.utf8)

    let settings = try JSONDecoder().decode(APIProjectTaskSyncSettings.self, from: data)
    #expect(settings.source == nil)
    #expect(settings.syncSchedule.intervalMinutes == 15)
}
