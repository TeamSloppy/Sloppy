import Foundation
import SwiftUI

public struct ConnectionSettings: Codable, Equatable, Sendable {
    public var coreURLString: String
    public var authToken: String
    public var defaultAgentID: String

    public init(
        coreURLString: String = "http://127.0.0.1:25101",
        authToken: String = "",
        defaultAgentID: String = "sloppy"
    ) {
        self.coreURLString = coreURLString
        self.authToken = authToken
        self.defaultAgentID = defaultAgentID
    }

    public mutating func normalize() {
        var url = coreURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty {
            url = "http://127.0.0.1:25101"
        } else if !url.contains("://") {
            url = "http://\(url)"
        }
        coreURLString = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        authToken = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let agent = defaultAgentID.trimmingCharacters(in: .whitespacesAndNewlines)
        defaultAgentID = agent.isEmpty ? "sloppy" : agent
    }
}

public final class ConnectionSettingsStore: ObservableObject {
    @Published public var settings: ConnectionSettings

    private let userDefaults: UserDefaults
    private let key = "SafariExtension.connectionSettings"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(ConnectionSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = ConnectionSettings()
        }
    }

    public func save() {
        var normalized = settings
        normalized.normalize()
        settings = normalized
        if let data = try? JSONEncoder().encode(normalized) {
            userDefaults.set(data, forKey: key)
        }
    }
}
