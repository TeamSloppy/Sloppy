import Foundation

struct SiteAccessPrincipal: Sendable, Equatable {
    var id: String
    var isAdmin: Bool
}

actor SiteBrowserSessionService {
    struct LaunchExchange: Sendable, Equatable {
        var sessionToken: String
        var returnTo: String
        var expiresAt: Date
    }

    private struct BrowserSession: Sendable {
        var principal: SiteAccessPrincipal
        var expiresAt: Date
    }

    private struct LaunchCode: Sendable {
        var principal: SiteAccessPrincipal
        var returnTo: String
        var expiresAt: Date
    }

    private var sessions: [String: BrowserSession] = [:]
    private var launchCodes: [String: LaunchCode] = [:]

    func createSession(
        principal: SiteAccessPrincipal,
        now: Date = Date(),
        lifetime: TimeInterval = 24 * 60 * 60
    ) -> (token: String, expiresAt: Date) {
        purgeExpired(now: now)
        let token = Self.secret(prefix: "slp_site_")
        let expiresAt = now.addingTimeInterval(lifetime)
        sessions[token] = BrowserSession(principal: principal, expiresAt: expiresAt)
        return (token, expiresAt)
    }

    func principal(forSessionToken token: String?, now: Date = Date()) -> SiteAccessPrincipal? {
        purgeExpired(now: now)
        guard let token, let session = sessions[token], session.expiresAt > now else { return nil }
        return session.principal
    }

    func createLaunchCode(
        principal: SiteAccessPrincipal,
        returnTo: String,
        now: Date = Date(),
        lifetime: TimeInterval = 60
    ) -> (code: String, expiresAt: Date) {
        purgeExpired(now: now)
        let code = Self.secret(prefix: "slp_launch_")
        let expiresAt = now.addingTimeInterval(lifetime)
        launchCodes[code] = LaunchCode(principal: principal, returnTo: returnTo, expiresAt: expiresAt)
        return (code, expiresAt)
    }

    func redeemLaunchCode(_ code: String, now: Date = Date()) -> LaunchExchange? {
        purgeExpired(now: now)
        guard let launch = launchCodes.removeValue(forKey: code), launch.expiresAt > now else { return nil }
        let session = createSession(principal: launch.principal, now: now)
        return LaunchExchange(
            sessionToken: session.token,
            returnTo: launch.returnTo,
            expiresAt: session.expiresAt
        )
    }

    func revokeSession(_ token: String?) {
        guard let token else { return }
        sessions[token] = nil
    }

    private func purgeExpired(now: Date) {
        sessions = sessions.filter { $0.value.expiresAt > now }
        launchCodes = launchCodes.filter { $0.value.expiresAt > now }
    }

    private static func secret(prefix: String) -> String {
        prefix + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}
