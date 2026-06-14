import Foundation
import Logging

enum CoffeeModePlatform: Sendable {
    case macOS
    case linux
    case other

    static var current: CoffeeModePlatform {
        #if os(macOS)
        return .macOS
        #elseif os(Linux)
        return .linux
        #else
        return .other
        #endif
    }
}

enum CoffeeModeActivityOption: Sendable, Equatable {
    case idleSystemSleepDisabled
    case idleDisplaySleepDisabled
}

struct CoffeeModeActivityToken: Sendable, Equatable, Hashable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

protocol CoffeeModeActivityClient: AnyObject {
    func begin(options: [CoffeeModeActivityOption], reason: String) -> CoffeeModeActivityToken
    func end(_ token: CoffeeModeActivityToken)
}

final class CoffeeModeHandle {
    private let client: CoffeeModeActivityClient
    private let token: CoffeeModeActivityToken
    private var ended = false

    init(client: CoffeeModeActivityClient, token: CoffeeModeActivityToken) {
        self.client = client
        self.token = token
    }

    func end() {
        guard !ended else { return }
        ended = true
        client.end(token)
    }

    deinit {
        end()
    }
}

final class CoffeeModeController {
    private let activityClient: CoffeeModeActivityClient
    private let platform: CoffeeModePlatform
    private var logger: Logger

    init(
        activityClient: CoffeeModeActivityClient = LiveCoffeeModeActivityClient(),
        platform: CoffeeModePlatform = .current,
        logger: Logger
    ) {
        self.activityClient = activityClient
        self.platform = platform
        self.logger = logger
    }

    func start(config: CoreConfig.CoffeeMode) -> CoffeeModeHandle? {
        guard config.enabled else {
            logger.info("Coffee Mode is disabled.")
            return nil
        }

        guard platform == .macOS else {
            logger.info("Coffee Mode is only supported on macOS; continuing without a power assertion.")
            return nil
        }

        var options: [CoffeeModeActivityOption] = [.idleSystemSleepDisabled]
        if config.preventDisplaySleep {
            options.append(.idleDisplaySleepDisabled)
        }

        let token = activityClient.begin(
            options: options,
            reason: "Sloppy Coffee Mode keeps agent work running while the server is active."
        )
        logger.info("Coffee Mode is active.")
        return CoffeeModeHandle(client: activityClient, token: token)
    }
}

final class LiveCoffeeModeActivityClient: CoffeeModeActivityClient {
    private let lock = NSLock()
    private var activities: [CoffeeModeActivityToken: any NSObjectProtocol] = [:]

    func begin(options: [CoffeeModeActivityOption], reason: String) -> CoffeeModeActivityToken {
        let token = CoffeeModeActivityToken()

        #if os(macOS)
        var activityOptions: ProcessInfo.ActivityOptions = [.idleSystemSleepDisabled]
        if options.contains(.idleDisplaySleepDisabled) {
            activityOptions.insert(.idleDisplaySleepDisabled)
        }
        let activity = ProcessInfo.processInfo.beginActivity(options: activityOptions, reason: reason)
        lock.lock()
        activities[token] = activity
        lock.unlock()
        #endif

        return token
    }

    func end(_ token: CoffeeModeActivityToken) {
        #if os(macOS)
        lock.lock()
        let activity = activities.removeValue(forKey: token)
        lock.unlock()

        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        #endif
    }
}
