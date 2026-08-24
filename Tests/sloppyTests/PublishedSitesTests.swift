import Foundation
import Testing
@testable import Protocols
@testable import sloppy

@Suite("Published sites")
struct PublishedSitesTests {
    @Test("lists only owner sites while admin can list all")
    func ownerFiltering() async {
        let service = CoreService(
            config: .test,
            persistenceBuilder: InMemoryCorePersistenceBuilder(),
            sharedSkillsRootURLs: []
        )
        let now = Date()
        for (id, owner) in [("one", "owner-1"), ("two", "owner-2")] {
            await service.store.savePublishedSite(PersistedPublishedSiteRecord(
                id: id,
                slug: id,
                title: id,
                visibility: .private,
                ownerId: owner,
                entryFile: "index.html",
                bundlePath: "sites/\(id)/current",
                revision: 1,
                createdAt: now,
                updatedAt: now
            ))
        }
        let owned = await service.listPublishedSites(
            principal: SiteAccessPrincipal(id: "owner-1", isAdmin: false)
        )
        let all = await service.listPublishedSites(
            principal: SiteAccessPrincipal(id: "admin", isAdmin: true)
        )
        #expect(owned.sites.map(\.id) == ["one"])
        #expect(all.sites.count == 2)
    }

    @Test("publishes nested static bundle and serves SPA fallback")
    func publishAndServe() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let build = root.appendingPathComponent("dist", isDirectory: true)
        try FileManager.default.createDirectory(
            at: build.appendingPathComponent("assets", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("<html>v1</html>".utf8).write(to: build.appendingPathComponent("index.html"))
        try Data("console.log('ok')".utf8).write(to: build.appendingPathComponent("assets/app.js"))

        let service = CoreService(
            config: .test,
            currentDirectory: root.path,
            persistenceBuilder: InMemoryCorePersistenceBuilder(),
            sharedSkillsRootURLs: []
        )
        let site = try await service.publishSite(
            sourceURL: build,
            siteID: nil,
            slug: "demo-site",
            title: "Demo Site",
            visibility: .public,
            ownerID: "local",
            projectID: "project-1",
            entryFile: "index.html"
        )
        #expect(site.path == "/sites/demo-site/")
        #expect(site.revision == 1)
        let workspaceRoot = await service.workspaceRootURL
        #expect(FileManager.default.fileExists(atPath: workspaceRoot
            .appendingPathComponent("sites/\(site.id)/current/index.html")
            .path))

        let router = CoreRouter(service: service)
        let rootResponse = await router.handle(method: "GET", path: "/sites/demo-site/", body: nil)
        #expect(rootResponse.status == 200)
        #expect(String(data: rootResponse.body, encoding: .utf8) == "<html>v1</html>")

        let assetResponse = await router.handle(method: "GET", path: "/sites/demo-site/assets/app.js", body: nil)
        #expect(assetResponse.status == 200)
        #expect(assetResponse.contentType == "application/javascript; charset=utf-8")

        let fallbackResponse = await router.handle(method: "GET", path: "/sites/demo-site/app/settings", body: nil)
        #expect(fallbackResponse.status == 200)
        #expect(String(data: fallbackResponse.body, encoding: .utf8) == "<html>v1</html>")

        let redirect = await router.handle(method: "GET", path: "/sites/demo-site", body: nil)
        #expect(redirect.status == 307)
        #expect(redirect.headers["location"] == "/sites/demo-site/")
    }

    @Test("failed update keeps current bundle")
    func atomicUpdate() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first", isDirectory: true)
        let invalid = root.appendingPathComponent("invalid", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: true)
        try Data("v1".utf8).write(to: first.appendingPathComponent("index.html"))

        let service = CoreService(
            config: .test,
            currentDirectory: root.path,
            persistenceBuilder: InMemoryCorePersistenceBuilder(),
            sharedSkillsRootURLs: []
        )
        let site = try await service.publishSite(
            sourceURL: first,
            siteID: nil,
            slug: "atomic",
            title: "Atomic",
            visibility: .public,
            ownerID: "local",
            projectID: nil,
            entryFile: "index.html"
        )

        await #expect(throws: PublishedSiteService.SiteError.invalidEntryFile) {
            try await service.publishSite(
                sourceURL: invalid,
                siteID: site.id,
                slug: "atomic",
                title: "Atomic",
                visibility: .public,
                ownerID: "local",
                projectID: nil,
                entryFile: "index.html"
            )
        }

        let persisted = try #require(await service.publishedSiteForServing(slug: "atomic"))
        let content = try #require(await service.publishedSiteContent(site: persisted, assetPath: ""))
        #expect(String(data: content.data, encoding: .utf8) == "v1")
    }

    @Test("private site requires browser session and launch code is single use")
    func privateAuthLaunch() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let build = root.appendingPathComponent("dist", isDirectory: true)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try Data("private".utf8).write(to: build.appendingPathComponent("index.html"))

        let service = CoreService(
            config: .test,
            currentDirectory: root.path,
            persistenceBuilder: InMemoryCorePersistenceBuilder(),
            sharedSkillsRootURLs: []
        )
        let site = try await service.publishSite(
            sourceURL: build,
            siteID: nil,
            slug: "private-site",
            title: "Private",
            visibility: .private,
            ownerID: "local",
            projectID: nil,
            entryFile: "index.html"
        )
        let router = CoreRouter(service: service)
        let denied = await router.handle(method: "GET", path: site.path, body: nil)
        #expect(denied.status == 303)
        #expect(denied.headers["location"]?.hasPrefix("/sites/auth/login") == true)

        let launch = try await service.createPublishedSiteLaunch(
            id: site.id,
            principal: SiteAccessPrincipal(id: "local", isAdmin: true)
        )
        let exchange = await router.handle(method: "GET", path: launch.url, body: nil)
        #expect(exchange.status == 303)
        let setCookie = try #require(exchange.headers["set-cookie"])
        let cookie = try #require(setCookie.split(separator: ";").first.map(String.init))
        let allowed = await router.handle(
            method: "GET",
            path: site.path,
            body: nil,
            headers: ["cookie": cookie]
        )
        #expect(allowed.status == 200)

        let replay = await router.handle(method: "GET", path: launch.url, body: nil)
        #expect(replay.status == 401)
    }

    @Test("rejects secrets and symbolic links from bundle")
    func rejectsUnsafeBundleEntries() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let build = root.appendingPathComponent("dist", isDirectory: true)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try Data("ok".utf8).write(to: build.appendingPathComponent("index.html"))
        try Data("secret".utf8).write(to: build.appendingPathComponent(".env.production"))

        #expect(throws: PublishedSiteService.SiteError.self) {
            try PublishedSiteService.installBundle(
                sourceURL: build,
                siteID: "unsafe",
                entryFile: "index.html",
                workspaceRootURL: root
            )
        }
    }

    @Test("honors configured bundle file limit")
    func configuredBundleLimit() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let build = root.appendingPathComponent("dist", isDirectory: true)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try Data("entry".utf8).write(to: build.appendingPathComponent("index.html"))
        try Data("asset".utf8).write(to: build.appendingPathComponent("asset.js"))
        var config = CoreConfig.test
        config.sites = CoreConfig.Sites(maximumFileCount: 1, maximumBundleBytes: 1024)
        let service = CoreService(
            config: config,
            currentDirectory: root.path,
            persistenceBuilder: InMemoryCorePersistenceBuilder(),
            sharedSkillsRootURLs: []
        )
        await #expect(throws: PublishedSiteService.SiteError.tooManyFiles) {
            try await service.publishSite(
                sourceURL: build,
                siteID: nil,
                slug: "limited",
                title: "Limited",
                visibility: .private,
                ownerID: "local",
                projectID: nil,
                entryFile: "index.html"
            )
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("published-sites-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@Test("published site persistence round trips through SQLite")
func publishedSiteSQLiteRoundTrip() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("published-sites-sqlite-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let schema = try String(
        contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/sloppy/Storage/schema.sql"),
        encoding: .utf8
    )
    let store = SQLiteStore(path: root.appendingPathComponent("core.sqlite").path, schemaSQL: schema)
    let now = Date()
    let record = PersistedPublishedSiteRecord(
        id: "site-1",
        slug: "round-trip",
        title: "Round Trip",
        visibility: .private,
        ownerId: "owner-1",
        projectId: "project-1",
        entryFile: "index.html",
        bundlePath: "sites/site-1/current",
        revision: 3,
        createdAt: now,
        updatedAt: now
    )
    await store.savePublishedSite(record)
    let loaded = try #require(await store.publishedSite(slug: "round-trip"))
    #expect(loaded.id == record.id)
    #expect(loaded.revision == 3)
    #expect(loaded.ownerId == "owner-1")
}
