import Foundation
import Protocols

extension CoreService: SiteToolService {
    func sitePrincipal(for request: HTTPRequest) async -> SiteAccessPrincipal? {
        if await identityAuthEnabled() {
            guard let actor = await CoreRouter.identityActor(for: request, service: self) else { return nil }
            return SiteAccessPrincipal(id: actor.user.id, isAdmin: actor.user.role == .admin)
        }
        guard validateDashboardAuthorizationHeader(request.header("authorization")) else { return nil }
        return SiteAccessPrincipal(id: "local", isAdmin: true)
    }

    func listPublishedSites(principal: SiteAccessPrincipal) async -> PublishedSiteListResponse {
        let records = await store.listPublishedSites()
            .filter { principal.isAdmin || $0.ownerId == principal.id }
            .map(Self.publishedSiteRecord)
        return PublishedSiteListResponse(sites: records)
    }

    func getPublishedSite(
        id: String,
        principal: SiteAccessPrincipal
    ) async throws -> PublishedSiteRecord {
        guard let site = await store.publishedSite(id: id) else {
            throw PublishedSiteService.SiteError.notFound
        }
        guard principal.isAdmin || site.ownerId == principal.id else {
            throw PublishedSiteService.SiteError.forbidden
        }
        return Self.publishedSiteRecord(site)
    }

    func updatePublishedSite(
        id: String,
        request: PublishedSiteUpdateRequest,
        principal: SiteAccessPrincipal
    ) async throws -> PublishedSiteRecord {
        guard var site = await store.publishedSite(id: id) else {
            throw PublishedSiteService.SiteError.notFound
        }
        guard principal.isAdmin || site.ownerId == principal.id else {
            throw PublishedSiteService.SiteError.forbidden
        }
        if let title = request.title {
            site.title = try PublishedSiteService.normalizedTitle(title)
        }
        if let rawSlug = request.slug {
            let slug = try PublishedSiteService.normalizedSlug(rawSlug)
            if let conflict = await store.publishedSite(slug: slug), conflict.id != site.id {
                throw PublishedSiteService.SiteError.slugConflict
            }
            site.slug = slug
        }
        if let visibility = request.visibility {
            site.visibility = visibility
        }
        site.updatedAt = Date()
        await store.savePublishedSite(site)
        return Self.publishedSiteRecord(site)
    }

    func deletePublishedSite(
        id: String,
        principal: SiteAccessPrincipal
    ) async throws {
        guard let site = await store.publishedSite(id: id) else {
            throw PublishedSiteService.SiteError.notFound
        }
        guard principal.isAdmin || site.ownerId == principal.id else {
            throw PublishedSiteService.SiteError.forbidden
        }
        do {
            try PublishedSiteService.removeBundle(siteID: site.id, workspaceRootURL: workspaceRootURL)
        } catch {
            throw PublishedSiteService.SiteError.storageFailure
        }
        guard await store.deletePublishedSite(id: id) else {
            throw PublishedSiteService.SiteError.storageFailure
        }
    }

    func publishSite(
        sourceURL: URL,
        siteID: String?,
        slug rawSlug: String,
        title rawTitle: String,
        visibility: PublishedSiteVisibility,
        ownerID: String,
        projectID: String?,
        entryFile rawEntryFile: String
    ) async throws -> PublishedSiteRecord {
        let slug = try PublishedSiteService.normalizedSlug(rawSlug)
        let title = try PublishedSiteService.normalizedTitle(rawTitle)
        let entryFile = try PublishedSiteService.normalizedEntryFile(rawEntryFile)
        let normalizedOwner = ownerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedOwner.isEmpty else { throw PublishedSiteService.SiteError.forbidden }

        let existing: PersistedPublishedSiteRecord?
        if let siteID = siteID?.trimmingCharacters(in: .whitespacesAndNewlines), !siteID.isEmpty {
            guard let found = await store.publishedSite(id: siteID) else {
                throw PublishedSiteService.SiteError.notFound
            }
            guard found.ownerId == normalizedOwner else {
                throw PublishedSiteService.SiteError.forbidden
            }
            existing = found
        } else {
            existing = nil
        }
        if let conflict = await store.publishedSite(slug: slug), conflict.id != existing?.id {
            throw PublishedSiteService.SiteError.slugConflict
        }

        let id = existing?.id ?? UUID().uuidString.lowercased()
        do {
            try PublishedSiteService.installBundle(
                sourceURL: sourceURL,
                siteID: id,
                entryFile: entryFile,
                workspaceRootURL: workspaceRootURL,
                limits: currentConfig.sites
            )
        } catch let error as PublishedSiteService.SiteError {
            throw error
        } catch {
            throw PublishedSiteService.SiteError.storageFailure
        }

        let now = Date()
        let site = PersistedPublishedSiteRecord(
            id: id,
            slug: slug,
            title: title,
            visibility: visibility,
            ownerId: normalizedOwner,
            projectId: projectID ?? existing?.projectId,
            entryFile: entryFile,
            bundlePath: PublishedSiteService.bundlePath(siteID: id),
            revision: (existing?.revision ?? 0) + 1,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        await store.savePublishedSite(site)
        return Self.publishedSiteRecord(site)
    }

    func createPublishedSiteLaunch(
        id: String,
        principal: SiteAccessPrincipal
    ) async throws -> PublishedSiteLaunchResponse {
        guard let site = await store.publishedSite(id: id) else {
            throw PublishedSiteService.SiteError.notFound
        }
        guard principal.isAdmin || site.ownerId == principal.id else {
            throw PublishedSiteService.SiteError.forbidden
        }
        let returnTo = "/sites/\(site.slug)/"
        if site.visibility == .public {
            return PublishedSiteLaunchResponse(url: returnTo)
        }
        let launch = await siteBrowserSessionService.createLaunchCode(
            principal: principal,
            returnTo: returnTo
        )
        let encoded = launch.code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? launch.code
        return PublishedSiteLaunchResponse(
            url: "/sites/auth/exchange?code=\(encoded)",
            expiresAt: launch.expiresAt
        )
    }

    func createSiteBrowserSession(
        login: String?,
        password: String?,
        token: String?
    ) async throws -> (token: String, expiresAt: Date) {
        let principal: SiteAccessPrincipal
        if await identityAuthEnabled() {
            let session = try await loginIdentityUser(
                AuthLoginRequest(login: login ?? "", password: password ?? "")
            )
            principal = SiteAccessPrincipal(
                id: session.user.id,
                isAdmin: session.user.role == .admin
            )
        } else {
            let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let dashboardToken = currentConfig.ui.dashboardAuth.token
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let legacyToken = currentConfig.auth.token
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let configuredTokens = [dashboardToken, legacyToken].filter { !$0.isEmpty }
            guard configuredTokens.isEmpty || configuredTokens.contains(trimmed) else {
                throw PublishedSiteService.SiteError.forbidden
            }
            principal = SiteAccessPrincipal(id: "local", isAdmin: true)
        }
        return await siteBrowserSessionService.createSession(principal: principal)
    }

    func redeemSiteLaunchCode(_ code: String) async -> SiteBrowserSessionService.LaunchExchange? {
        await siteBrowserSessionService.redeemLaunchCode(code)
    }

    func siteBrowserPrincipal(sessionToken: String?) async -> SiteAccessPrincipal? {
        await siteBrowserSessionService.principal(forSessionToken: sessionToken)
    }

    func revokeSiteBrowserSession(_ token: String?) async {
        await siteBrowserSessionService.revokeSession(token)
    }

    func publishedSiteForServing(slug: String) async -> PersistedPublishedSiteRecord? {
        await store.publishedSite(slug: slug)
    }

    func publishedSiteContent(
        site: PersistedPublishedSiteRecord,
        assetPath: String
    ) -> PublishedSiteService.Content? {
        PublishedSiteService.content(
            site: site,
            assetPath: assetPath,
            workspaceRootURL: workspaceRootURL
        )
    }

    nonisolated static func canAccessPublishedSite(
        _ site: PersistedPublishedSiteRecord,
        principal: SiteAccessPrincipal?
    ) -> Bool {
        site.visibility == .public
            || principal?.isAdmin == true
            || principal?.id == site.ownerId
    }

    nonisolated static func safeSiteReturnPath(_ raw: String?) -> String {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard value.hasPrefix("/sites/"),
              !value.hasPrefix("//"),
              !value.contains("\r"),
              !value.contains("\n")
        else { return "/sites/" }
        return value
    }

    nonisolated static func publishedSiteRecord(
        _ record: PersistedPublishedSiteRecord
    ) -> PublishedSiteRecord {
        PublishedSiteRecord(
            id: record.id,
            slug: record.slug,
            title: record.title,
            visibility: record.visibility,
            ownerId: record.ownerId,
            projectId: record.projectId,
            entryFile: record.entryFile,
            revision: record.revision,
            path: "/sites/\(record.slug)/",
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }
}
