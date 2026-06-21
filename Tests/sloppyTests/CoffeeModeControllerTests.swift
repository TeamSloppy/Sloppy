import Foundation
import Logging
import Testing
@testable import sloppy

@Test
func coffeeModeControllerDoesNotStartWhenDisabled() {
    let activityClient = RecordingCoffeeModeActivityClient()
    let controller = CoffeeModeController(
        activityClient: activityClient,
        platform: .macOS,
        logger: .sloppy(label: "sloppy.tests.coffee")
    )

    let handle = controller.start(config: .init(enabled: false))

    #expect(handle == nil)
    #expect(activityClient.startedOptions.isEmpty)
}

@Test
func coffeeModeControllerStartsIdleSystemSleepActivity() throws {
    let activityClient = RecordingCoffeeModeActivityClient()
    let controller = CoffeeModeController(
        activityClient: activityClient,
        platform: .macOS,
        logger: .sloppy(label: "sloppy.tests.coffee")
    )

    let handle = try #require(controller.start(config: .init(enabled: true)))

    #expect(activityClient.startedOptions == [.idleSystemSleepDisabled])
    #expect(activityClient.endedHandles.isEmpty)

    handle.end()

    #expect(activityClient.endedHandles.count == 1)
}

@Test
func coffeeModeControllerIncludesDisplaySleepWhenConfigured() throws {
    let activityClient = RecordingCoffeeModeActivityClient()
    let controller = CoffeeModeController(
        activityClient: activityClient,
        platform: .macOS,
        logger: .sloppy(label: "sloppy.tests.coffee")
    )

    _ = try #require(controller.start(config: .init(enabled: true, preventDisplaySleep: true)))

    #expect(activityClient.startedOptions == [.idleSystemSleepDisabled, .idleDisplaySleepDisabled])
}

@Test
func coffeeModeControllerNoopsOnLinux() {
    let activityClient = RecordingCoffeeModeActivityClient()
    let controller = CoffeeModeController(
        activityClient: activityClient,
        platform: .linux,
        logger: .sloppy(label: "sloppy.tests.coffee")
    )

    let handle = controller.start(config: .init(enabled: true))

    #expect(handle == nil)
    #expect(activityClient.startedOptions.isEmpty)
}

private final class RecordingCoffeeModeActivityClient: CoffeeModeActivityClient {
    var startedOptions: [CoffeeModeActivityOption] = []
    var endedHandles: [CoffeeModeActivityToken] = []

    func begin(options: [CoffeeModeActivityOption], reason: String) -> CoffeeModeActivityToken {
        startedOptions = options
        return CoffeeModeActivityToken(rawValue: UUID())
    }

    func end(_ token: CoffeeModeActivityToken) {
        endedHandles.append(token)
    }
}
