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
    case superseded
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
    private struct RefreshOperation {
        let id = UUID()
        let task: Task<AuthSession?, any Error>
    }
    private var refreshTasks: [String: RefreshOperation] = [:]
    private var sessionRevisions: [String: UUID] = [:]

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
        invalidateRecovery(forKey: key)
        loadedServerKeys.insert(key)
        sessions[key] = session
        persist(session, forKey: key)
    }

    public func updateUser(_ user: AuthUserProfile, for baseURL: URL) {
        let key = Self.serverKey(for: baseURL)
        loadSessionIfNeeded(forKey: key)
        guard var session = sessions[key] else { return }
        session.user = user
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
        invalidateRecovery(forKey: key)
        loadedServerKeys.insert(key)
        sessions[key] = nil
        deletePersistedSession(forKey: key)
    }

    public func recoverSession(
        for baseURL: URL,
        rejectedAccessToken: String?,
        refresh: @escaping @Sendable (String) async -> AuthSession?
    ) async -> AuthSessionRecoveryResult {
        // Preserve the nonthrowing API for callers whose refresh callback cannot fail transiently.
        (try? await recoverSession(for: baseURL, rejectedAccessToken: rejectedAccessToken,
                                  refreshSession: refresh)) ?? .unavailable
    }

    public func recoverSession(
        for baseURL: URL,
        rejectedAccessToken: String?,
        refreshSession: @escaping @Sendable (String) async throws -> AuthSession?
    ) async throws -> AuthSessionRecoveryResult {
        let key = Self.serverKey(for: baseURL)
        loadSessionIfNeeded(forKey: key)
        let revision = sessionRevisions[key]

        if let current = sessions[key],
           let rejectedAccessToken,
           current.accessToken != rejectedAccessToken {
            return .recovered(current)
        }

        guard let current = sessions[key] else {
            return .unavailable
        }
        let refreshToken = current.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !refreshToken.isEmpty else {
            clear(for: baseURL)
            return .failed
        }

        let operation: RefreshOperation
        if let running = refreshTasks[key] {
            operation = running
        } else {
            operation = RefreshOperation(task: Task { try await refreshSession(refreshToken) })
            refreshTasks[key] = operation
        }
        let refreshed: AuthSession?
        do {
            refreshed = try await operation.task.value
        } catch {
            guard sessionRevisions[key] == revision else { return .superseded }
            if refreshTasks[key]?.id == operation.id { refreshTasks[key] = nil }
            throw error
        }
        guard sessionRevisions[key] == revision else { return .superseded }
        if refreshTasks[key]?.id == operation.id { refreshTasks[key] = nil }

        guard let refreshed else {
            clear(for: baseURL)
            return .failed
        }

        loadedServerKeys.insert(key)
        sessions[key] = refreshed
        persist(refreshed, forKey: key)
        return .recovered(refreshed)
    }

    private func invalidateRecovery(forKey key: String) {
        sessionRevisions[key] = UUID()
        refreshTasks.removeValue(forKey: key)?.task.cancel()
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
