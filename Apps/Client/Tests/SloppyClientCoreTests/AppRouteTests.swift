import Testing
@testable import SloppyClientCore

@Suite("AppRoute")
struct AppRouteTests {

    @Test("all cases present")
    func allCasesPresent() {
        let routes = AppRoute.allCases
        #expect(routes.count == 5)
        #expect(routes.contains(.overview))
        #expect(routes.contains(.projects))
        #expect(routes.contains(.agents))
        #expect(routes.contains(.tasks))
        #expect(routes.contains(.review))
    }

    @Test("each route has non-empty title and icon")
    func titlesAndIcons() {
        for route in AppRoute.allCases {
            #expect(!route.title.isEmpty)
            #expect(!route.systemImage.isEmpty)
        }
    }

    @Test("id matches rawValue")
    func idMatchesRawValue() {
        for route in AppRoute.allCases {
            #expect(route.id == route.rawValue)
        }
    }

    @Test("routes are hashable and equatable")
    func hashableEquatable() {
        let a = AppRoute.overview
        let b = AppRoute.overview
        let c = AppRoute.agents
        #expect(a == b)
        #expect(a != c)

        var set = Set<AppRoute>()
        set.insert(a)
        set.insert(b)
        #expect(set.count == 1)
    }
}
