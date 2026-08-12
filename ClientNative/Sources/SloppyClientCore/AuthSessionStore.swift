import Foundation
#if canImport(Security)
import Security
#endif

public enum AuthSessionPersistence: Sendable {
    case keychain
    case memory
}

public enum AuthSessionRecoveryResult: Sendable, Equatable {
    case recovered(AuthSession)
    case failed
    case unavailable
}

public enum AuthSessionNotifications {
    public static let authenticationRequired = Notification.Name(
        "SloppyClientCore.authenticationRequired"
    )
    public static let baseURLUserInfoKey = "baseURL"
}

public actor AuthSessionStore {
    public static let shared = AuthSessionStore()

    private static let keychainService = "team.sloppy.client.auth-session"

    private let persistence: AuthSessionPersistence
    private var sessions: [String: AuthSession] = [:]
    private var loadedServerKeys: Set<String> = []
    private var refreshTasks: [String: Task<AuthSession?, Never>] = [:]

    public init(persistence: AuthSessionPersistence = .keychain) {
        self.persistence = persistence
    }

    public func session(for baseURL: URL) -> AuthSession? {
        let key = Self.serverKey(for: baseURL)
        loadSessionIfNeeded(forKey: key)
        return sessions[key]
    }

    public func save(_ session: AuthSession, for baseURL: URL) {
        let key = Self.serverKey(for: baseURL)
        loadedServerKeys.insert(key)
        sessions[key] = session
        persist(session, forKey: key)
    }

    public func saveStaticToken(_ token: String, for baseURL: URL) {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            clear(for: baseURL)
            return
        }
        save(
            AuthSession(accessToken: normalized, refreshToken: ""),
            for: baseURL
        )
    }

    public func clear(for baseURL: URL) {
        let key = Self.serverKey(for: baseURL)
        refreshTasks[key]?.cancel()
        refreshTasks[key] = nil
        loadedServerKeys.insert(key)
        sessions[key] = nil
        deletePersistedSession(forKey: key)
    }

    public func recoverSession(
        for baseURL: URL,
        rejectedAccessToken: String?,
        refresh: @escaping @Sendable (String) async -> AuthSession?
    ) async -> AuthSessionRecoveryResult {
        let key = Self.serverKey(for: baseURL)
        loadSessionIfNeeded(forKey: key)

        if let current = sessions[key],
           let rejectedAccessToken,
           current.accessToken != rejectedAccessToken {
            return .recovered(current)
        }

        if let refreshTask = refreshTasks[key] {
            if let session = await refreshTask.value {
                return .recovered(session)
            }
            return .failed
        }

        guard let current = sessions[key] else {
            return .unavailable
        }
        let refreshToken = current.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !refreshToken.isEmpty else {
            clear(for: baseURL)
            return .failed
        }

        let refreshTask = Task { await refresh(refreshToken) }
        refreshTasks[key] = refreshTask
        let refreshed = await refreshTask.value
        refreshTasks[key] = nil

        guard let refreshed else {
            loadedServerKeys.insert(key)
            sessions[key] = nil
            deletePersistedSession(forKey: key)
            return .failed
        }

        loadedServerKeys.insert(key)
        sessions[key] = refreshed
        persist(refreshed, forKey: key)
        return .recovered(refreshed)
    }

    private static func serverKey(for baseURL: URL) -> String {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL.absoluteString
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return components.url?.absoluteString ?? baseURL.absoluteString
    }

    private func loadSessionIfNeeded(forKey key: String) {
        guard !loadedServerKeys.contains(key) else { return }
        loadedServerKeys.insert(key)
        guard persistence == .keychain,
              let data = keychainData(forKey: key),
              let session = try? JSONDecoder().decode(AuthSession.self, from: data) else {
            return
        }
        sessions[key] = session
    }

    private func persist(_ session: AuthSession, forKey key: String) {
        guard persistence == .keychain,
              let data = try? JSONEncoder().encode(session) else {
            return
        }
        setKeychainData(data, forKey: key)
    }

    private func deletePersistedSession(forKey key: String) {
        guard persistence == .keychain else { return }
        deleteKeychainData(forKey: key)
    }

    private func keychainData(forKey key: String) -> Data? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: key,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
        #else
        return nil
        #endif
    }

    private func setKeychainData(_ data: Data, forKey key: String) {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: key,
        ]
        let update: [String: Any] = [
            kSecValueData as String: data,
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        guard status == errSecItemNotFound else { return }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
        #endif
    }

    private func deleteKeychainData(forKey key: String) {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        #endif
    }
}
