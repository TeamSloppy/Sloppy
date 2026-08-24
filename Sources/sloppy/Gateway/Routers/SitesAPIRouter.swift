import Foundation
import Protocols

struct SitesAPIRouter: APIRouter {
    private static let cookieName = "sloppy_site_session"
    private let service: CoreService

    init(service: CoreService) {
        self.service = service
    }

    func configure(on router: CoreRouterRegistrar) {
        router.get("/v1/sites", metadata: RouteMetadata(
            summary: "List published sites",
            description: "Lists sites owned by the authenticated user",
            tags: ["Sites"]
        )) { request in
            guard let principal = await service.sitePrincipal(for: request) else {
                return CoreRouter.json(status: HTTPStatus.unauthorized, payload: ["error": ErrorCode.unauthorized])
            }
            return CoreRouter.encodable(
                status: HTTPStatus.ok,
                payload: await service.listPublishedSites(principal: principal)
            )
        }

        router.get("/v1/sites/:siteId", metadata: RouteMetadata(
            summary: "Get published site",
            description: "Returns published site metadata",
            tags: ["Sites"]
        )) { request in
            guard let principal = await service.sitePrincipal(for: request) else {
                return CoreRouter.json(status: HTTPStatus.unauthorized, payload: ["error": ErrorCode.unauthorized])
            }
            do {
                let site = try await service.getPublishedSite(
                    id: request.pathParam("siteId") ?? "",
                    principal: principal
                )
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: PublishedSiteDetailResponse(site: site))
            } catch {
                return Self.siteErrorResponse(error)
            }
        }

        router.patch("/v1/sites/:siteId", metadata: RouteMetadata(
            summary: "Update published site",
            description: "Updates title, slug, or visibility for a published site",
            tags: ["Sites"]
        )) { request in
            guard let principal = await service.sitePrincipal(for: request) else {
                return CoreRouter.json(status: HTTPStatus.unauthorized, payload: ["error": ErrorCode.unauthorized])
            }
            guard let payload = request.decode(PublishedSiteUpdateRequest.self) else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                let site = try await service.updatePublishedSite(
                    id: request.pathParam("siteId") ?? "",
                    request: payload,
                    principal: principal
                )
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: PublishedSiteDetailResponse(site: site))
            } catch {
                return Self.siteErrorResponse(error)
            }
        }

        router.delete("/v1/sites/:siteId", metadata: RouteMetadata(
            summary: "Delete published site",
            description: "Deletes published site metadata and its static bundle",
            tags: ["Sites"]
        )) { request in
            guard let principal = await service.sitePrincipal(for: request) else {
                return CoreRouter.json(status: HTTPStatus.unauthorized, payload: ["error": ErrorCode.unauthorized])
            }
            do {
                try await service.deletePublishedSite(
                    id: request.pathParam("siteId") ?? "",
                    principal: principal
                )
                return CoreRouter.encodable(
                    status: HTTPStatus.ok,
                    payload: PublishedSiteDeleteResponse(deleted: true)
                )
            } catch {
                return Self.siteErrorResponse(error)
            }
        }

        router.post("/v1/sites/:siteId/launch", metadata: RouteMetadata(
            summary: "Create site launch URL",
            description: "Creates a one-time browser launch exchange for a private site",
            tags: ["Sites"]
        )) { request in
            guard let principal = await service.sitePrincipal(for: request) else {
                return CoreRouter.json(status: HTTPStatus.unauthorized, payload: ["error": ErrorCode.unauthorized])
            }
            do {
                return CoreRouter.encodable(
                    status: HTTPStatus.ok,
                    payload: try await service.createPublishedSiteLaunch(
                        id: request.pathParam("siteId") ?? "",
                        principal: principal
                    )
                )
            } catch {
                return Self.siteErrorResponse(error)
            }
        }

        router.get("/sites/auth/login", metadata: RouteMetadata(
            summary: "Published site login",
            description: "Displays the browser login form for private sites",
            tags: ["Sites"]
        )) { request in
            let returnTo = CoreService.safeSiteReturnPath(request.queryParam("returnTo"))
            let identityEnabled = await service.identityAuthEnabled()
            return Self.loginPage(identityEnabled: identityEnabled, returnTo: returnTo)
        }

        router.post("/sites/auth/login", metadata: RouteMetadata(
            summary: "Authenticate published site browser",
            description: "Creates an HttpOnly browser session for private sites",
            tags: ["Sites"]
        )) { request in
            let form = Self.parseForm(request.body)
            let returnTo = CoreService.safeSiteReturnPath(form["returnTo"])
            do {
                let session = try await service.createSiteBrowserSession(
                    login: form["login"],
                    password: form["password"],
                    token: form["token"]
                )
                return Self.redirect(
                    to: returnTo,
                    status: HTTPStatus.seeOther,
                    cookie: Self.sessionCookie(
                        token: session.token,
                        expiresAt: session.expiresAt,
                        request: request
                    )
                )
            } catch {
                return Self.loginPage(
                    identityEnabled: await service.identityAuthEnabled(),
                    returnTo: returnTo,
                    error: "Authentication failed.",
                    status: HTTPStatus.unauthorized
                )
            }
        }

        router.get("/sites/auth/exchange", metadata: RouteMetadata(
            summary: "Redeem site launch code",
            description: "Consumes a one-time launch code and creates a browser session",
            tags: ["Sites"]
        )) { request in
            guard let code = request.queryParam("code"),
                  let exchange = await service.redeemSiteLaunchCode(code)
            else {
                return CoreRouterResponse(
                    status: HTTPStatus.unauthorized,
                    body: Data("Invalid or expired launch link".utf8),
                    contentType: "text/plain; charset=utf-8"
                )
            }
            return Self.redirect(
                to: CoreService.safeSiteReturnPath(exchange.returnTo),
                status: HTTPStatus.seeOther,
                cookie: Self.sessionCookie(
                    token: exchange.sessionToken,
                    expiresAt: exchange.expiresAt,
                    request: request
                )
            )
        }

        router.get("/sites/auth/logout", metadata: RouteMetadata(
            summary: "Log out from published sites",
            description: "Revokes the current browser site session",
            tags: ["Sites"]
        )) { request in
            let token = Self.cookie(named: Self.cookieName, request: request)
            await service.revokeSiteBrowserSession(token)
            return Self.redirect(
                to: "/sites/auth/login",
                status: HTTPStatus.seeOther,
                cookie: "\(Self.cookieName)=; Path=/sites; HttpOnly; SameSite=Lax; Max-Age=0"
            )
        }

        registerContentRoutes(on: router)
    }

    private func registerContentRoutes(on router: CoreRouterRegistrar) {
        let rootHandler: (HTTPRequest) async -> CoreRouterResponse = { request in
            let slug = request.pathParam("slug") ?? ""
            let rawPath = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? request.path
            guard rawPath.hasSuffix("/") else {
                return Self.redirect(to: "/sites/\(slug)/", status: HTTPStatus.temporaryRedirect)
            }
            return await Self.contentResponse(request: request, assetPath: "", service: service)
        }
        let assetHandler: (HTTPRequest) async -> CoreRouterResponse = { request in
            await Self.contentResponse(
                request: request,
                assetPath: request.pathParam("assetPath") ?? "",
                service: service
            )
        }
        router.get("/sites/:slug", metadata: Self.contentMetadata, callback: rootHandler)
        router.head("/sites/:slug", metadata: Self.contentMetadata, callback: rootHandler)
        router.get("/sites/:slug/*assetPath", metadata: Self.contentMetadata, callback: assetHandler)
        router.head("/sites/:slug/*assetPath", metadata: Self.contentMetadata, callback: assetHandler)
    }

    private static var contentMetadata: RouteMetadata {
        RouteMetadata(
            summary: "Serve published site content",
            description: "Serves a file from a published static site bundle",
            tags: ["Sites"]
        )
    }

    private static func contentResponse(
        request: HTTPRequest,
        assetPath: String,
        service: CoreService
    ) async -> CoreRouterResponse {
        guard let site = await service.publishedSiteForServing(slug: request.pathParam("slug") ?? "") else {
            return CoreRouterResponse(
                status: HTTPStatus.notFound,
                body: Data("Not found".utf8),
                contentType: "text/plain; charset=utf-8"
            )
        }
        let principal = await service.siteBrowserPrincipal(
            sessionToken: cookie(named: cookieName, request: request)
        )
        guard CoreService.canAccessPublishedSite(site, principal: principal) else {
            if principal == nil {
                let returnTo = CoreService.safeSiteReturnPath(
                    "/sites/\(site.slug)/" + assetPath
                )
                let encoded = returnTo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? returnTo
                return redirect(
                    to: "/sites/auth/login?returnTo=\(encoded)",
                    status: HTTPStatus.seeOther
                )
            }
            return CoreRouterResponse(
                status: HTTPStatus.forbidden,
                body: Data("Forbidden".utf8),
                contentType: "text/plain; charset=utf-8"
            )
        }
        guard let content = await service.publishedSiteContent(site: site, assetPath: assetPath) else {
            return CoreRouterResponse(
                status: HTTPStatus.notFound,
                body: Data("Not found".utf8),
                contentType: "text/plain; charset=utf-8"
            )
        }
        return CoreRouterResponse(
            status: HTTPStatus.ok,
            body: content.data,
            contentType: content.mediaType,
            headers: [
                "cache-control": content.mediaType.hasPrefix("text/html") ? "no-cache" : "public, max-age=300",
                "x-content-type-options": "nosniff",
                "referrer-policy": "same-origin",
            ]
        )
    }

    private static func siteErrorResponse(_ error: Error) -> CoreRouterResponse {
        guard let error = error as? PublishedSiteService.SiteError else {
            return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": "site_operation_failed"])
        }
        switch error {
        case .notFound:
            return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": "site_not_found"])
        case .forbidden:
            return CoreRouter.json(status: HTTPStatus.forbidden, payload: ["error": "forbidden"])
        case .slugConflict:
            return CoreRouter.json(status: HTTPStatus.conflict, payload: ["error": "site_slug_conflict"])
        case .invalidSlug, .invalidTitle, .invalidEntryFile, .invalidSource,
             .forbiddenSourceEntry, .bundleTooLarge, .tooManyFiles:
            return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": "invalid_site"])
        case .storageFailure:
            return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": "site_storage_failed"])
        }
    }

    private static func redirect(to location: String, status: Int, cookie: String? = nil) -> CoreRouterResponse {
        var headers = ["location": location]
        if let cookie { headers["set-cookie"] = cookie }
        return CoreRouterResponse(
            status: status,
            body: Data(),
            contentType: "text/plain; charset=utf-8",
            headers: headers
        )
    }

    private static func sessionCookie(token: String, expiresAt: Date, request: HTTPRequest) -> String {
        var attributes = [
            "\(cookieName)=\(token)",
            "Path=/sites",
            "HttpOnly",
            "SameSite=Lax",
            "Expires=\(cookieDateFormatter.string(from: expiresAt))",
        ]
        if request.header("x-forwarded-proto")?.lowercased() == "https" {
            attributes.append("Secure")
        }
        return attributes.joined(separator: "; ")
    }

    private static func cookie(named name: String, request: HTTPRequest) -> String? {
        request.header("cookie")?
            .split(separator: ";")
            .compactMap { pair -> (String, String)? in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return (parts[0].trimmingCharacters(in: .whitespaces), parts[1])
            }
            .first { $0.0 == name }?.1
    }

    private static func parseForm(_ body: Data?) -> [String: String] {
        guard let body, let value = String(data: body, encoding: .utf8) else { return [:] }
        return value.split(separator: "&").reduce(into: [:]) { result, pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            let key = formDecoded(parts.first ?? "")
            guard !key.isEmpty else { return }
            result[key] = formDecoded(parts.count > 1 ? parts[1] : "")
        }
    }

    private static func formDecoded(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value
    }

    private static func loginPage(
        identityEnabled: Bool,
        returnTo: String,
        error: String? = nil,
        status: Int = HTTPStatus.ok
    ) -> CoreRouterResponse {
        let fields = identityEnabled
            ? """
              <label>Login<input name="login" autocomplete="username" required></label>
              <label>Password<input name="password" type="password" autocomplete="current-password" required></label>
              """
            : """
              <label>Sloppy access token<input name="token" type="password" autocomplete="current-password"></label>
              """
        let errorHTML = error.map { "<p class=\"error\">\(htmlEscaped($0))</p>" } ?? ""
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
        <title>Sign in to Sloppy</title><style>
        :root{color-scheme:light dark}body{font:16px system-ui;margin:0;min-height:100vh;display:grid;place-items:center;background:#151515;color:#eee}
        form{width:min(360px,calc(100vw - 48px));padding:28px;border:1px solid #444;border-radius:18px;background:#222;display:grid;gap:16px}
        h1{margin:0;font-size:24px}label{display:grid;gap:7px;color:#bbb}input{font:inherit;padding:11px;border:1px solid #555;border-radius:9px;background:#181818;color:#fff}
        button{font:inherit;padding:11px;border:0;border-radius:9px;background:#35c8f0;color:#07161a;font-weight:600}.error{color:#ff8b8b;margin:0}
        </style></head><body><form method="post" action="/sites/auth/login"><h1>Sign in to Sloppy</h1>
        \(errorHTML)\(fields)<input type="hidden" name="returnTo" value="\(htmlEscaped(returnTo))"><button type="submit">Continue</button>
        </form></body></html>
        """
        return CoreRouterResponse(status: status, body: Data(html.utf8), contentType: "text/html; charset=utf-8")
    }

    private static func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static let cookieDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter
    }()
}
