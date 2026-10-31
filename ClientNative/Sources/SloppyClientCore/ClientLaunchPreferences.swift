import Foundation
import Observation

public enum ClientLaunchMode: String, Sendable {
    case instance
    case browser
}

/// Kept separately from server credentials so browsing never requires an instance.
@Observable
@MainActor
public final class ClientLaunchPreferences {
    private let defaults: UserDefaults
    public private(set) var hasCompletedWelcome: Bool
    public private(set) var mode: ClientLaunchMode
    public var hasConfiguredInstance: Bool {
        didSet { defaults.set(hasConfiguredInstance, forKey: "client_has_configured_instance") }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompletedWelcome = defaults.bool(forKey: "client_welcome_completed")
        mode = defaults.string(forKey: "client_launch_mode").flatMap(ClientLaunchMode.init(rawValue:)) ?? .instance
        hasConfiguredInstance = defaults.bool(forKey: "client_has_configured_instance")
    }

    public func completeWelcome(mode: ClientLaunchMode) {
        self.mode = mode
        hasCompletedWelcome = true
        defaults.set(mode.rawValue, forKey: "client_launch_mode")
        defaults.set(true, forKey: "client_welcome_completed")
    }
}

public enum AgentConnectionStatus: Equatable, Sendable {
    case notConfigured
    case waiting
    case failed(String)
    case connected

    public static func resolve(configured: Bool, connected: Bool, failure: String?) -> Self {
        if !configured { return .notConfigured }
        if let failure { return .failed(failure) }
        return connected ? .connected : .waiting
    }
}
