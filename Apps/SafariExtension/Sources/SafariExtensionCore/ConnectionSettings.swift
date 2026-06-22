import Foundation
import SwiftUI

public struct ConnectionSettings: Codable, Equatable, Sendable {
    public var coreURLString: String
    public var authToken: String
    public var defaultAgentID: String

    public static var isLocalhostDefaultAvailableByDefault: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    public static func defaultCoreURLString(isLocalhostDefaultAvailable: Bool) -> String {
        isLocalhostDefaultAvailable ? "http://127.0.0.1:25101" : ""
    }

    public init(
        coreURLString: String? = nil,
        authToken: String = "",
        defaultAgentID: String = "sloppy",
        isLocalhostDefaultAvailable: Bool = ConnectionSettings.isLocalhostDefaultAvailableByDefault
    ) {
        self.coreURLString = coreURLString ?? Self.defaultCoreURLString(
            isLocalhostDefaultAvailable: isLocalhostDefaultAvailable
        )
        self.authToken = authToken
        self.defaultAgentID = defaultAgentID
    }

    public mutating func normalize() {
        self = normalized()
    }

    public mutating func normalize(isLocalhostDefaultAvailable: Bool) {
        self = normalized(isLocalhostDefaultAvailable: isLocalhostDefaultAvailable)
    }

    public func normalized() -> ConnectionSettings {
        normalized(isLocalhostDefaultAvailable: Self.isLocalhostDefaultAvailableByDefault)
    }

    public func normalized(isLocalhostDefaultAvailable: Bool) -> ConnectionSettings {
        var normalized = self
        var url = coreURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty {
            url = Self.defaultCoreURLString(
                isLocalhostDefaultAvailable: isLocalhostDefaultAvailable
            )
        } else if !url.contains("://") {
            url = "http://\(url)"
        }
        normalized.coreURLString = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        normalized.authToken = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let agent = defaultAgentID.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.defaultAgentID = agent.isEmpty ? "sloppy" : agent
        return normalized
    }
}

public final class ConnectionSettingsStore: ObservableObject {
    @Published public var settings: ConnectionSettings

    private let userDefaults: UserDefaults
    private let isLocalhostDefaultAvailable: Bool
    private let key = "SafariExtension.connectionSettings"

    public init(
        userDefaults: UserDefaults = .standard,
        isLocalhostDefaultAvailable: Bool = ConnectionSettings.isLocalhostDefaultAvailableByDefault
    ) {
        self.userDefaults = userDefaults
        self.isLocalhostDefaultAvailable = isLocalhostDefaultAvailable
        if let data = userDefaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(ConnectionSettings.self, from: data) {
            self.settings = decoded.normalized(
                isLocalhostDefaultAvailable: isLocalhostDefaultAvailable
            )
        } else {
            self.settings = ConnectionSettings(
                isLocalhostDefaultAvailable: isLocalhostDefaultAvailable
            )
        }
    }

    public func save() {
        let normalized = settings.normalized(
            isLocalhostDefaultAvailable: isLocalhostDefaultAvailable
        )
        settings = normalized
        if let data = try? JSONEncoder().encode(normalized) {
            userDefaults.set(data, forKey: key)
        }
    }
}
