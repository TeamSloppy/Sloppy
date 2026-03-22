import Testing
@testable import sloppy
@testable import Protocols

@Test
func swarmCoordinatorUsesOnlyHierarchicalOneWayTaskLinks() {
    let links: [ActorLink] = [
        ActorLink(
            id: "root-child",
            sourceActorId: "agent:root",
            targetActorId: "agent:child",
            direction: .oneWay,
            relationship: .hierarchical,
            communicationType: .task
        ),
        ActorLink(
            id: "root-peer",
            sourceActorId: "agent:root",
            targetActorId: "agent:peer",
            direction: .oneWay,
            relationship: .peer,
            communicationType: .task
        ),
        ActorLink(
            id: "root-non-task",
            sourceActorId: "agent:root",
            targetActorId: "agent:other",
            direction: .oneWay,
            relationship: .hierarchical,
            communicationType: .chat
        )
    ]

    let result = SwarmCoordinator.buildHierarchy(rootActorId: "agent:root", links: links)
    guard case .hierarchy(let hierarchy) = result else {
        Issue.record("Expected hierarchy result, got \(result)")
        return
    }

    #expect(hierarchy.levels == [["agent:child"]])
    #expect(hierarchy.parentByActor["agent:child"] == "agent:root")
    #expect(hierarchy.parentByActor["agent:peer"] == nil)
}

@Test
func swarmCoordinatorInfersHierarchicalFallbackFromSockets() {
    let links: [ActorLink] = [
        ActorLink(
            id: "fallback-link",
            sourceActorId: "agent:root",
            targetActorId: "agent:child",
            direction: .oneWay,
            relationship: nil,
            communicationType: .task,
            sourceSocket: .bottom,
            targetSocket: .top
        )
    ]

    let result = SwarmCoordinator.buildHierarchy(rootActorId: "agent:root", links: links)
    guard case .hierarchy(let hierarchy) = result else {
        Issue.record("Expected hierarchy result, got \(result)")
        return
    }

    #expect(hierarchy.levels == [["agent:child"]])
}

@Test
func swarmCoordinatorIgnoresHierarchicalTwoWayAsAmbiguous() {
    let links: [ActorLink] = [
        ActorLink(
            id: "ambiguous-link",
            sourceActorId: "agent:root",
            targetActorId: "agent:child",
            direction: .twoWay,
            relationship: .hierarchical,
            communicationType: .task
        )
    ]

    let result = SwarmCoordinator.buildHierarchy(rootActorId: "agent:root", links: links)
    #expect(result == .noHierarchy)
}

@Test
func swarmCoordinatorDetectsReachableCycle() {
    let links: [ActorLink] = [
        ActorLink(
            id: "root-child",
            sourceActorId: "agent:root",
            targetActorId: "agent:child",
            direction: .oneWay,
            relationship: .hierarchical,
            communicationType: .task
        ),
        ActorLink(
            id: "child-root",
            sourceActorId: "agent:child",
            targetActorId: "agent:root",
            direction: .oneWay,
            relationship: .hierarchical,
            communicationType: .task
        )
    ]

    let result = SwarmCoordinator.buildHierarchy(rootActorId: "agent:root", links: links)
    #expect(result == .cycle)
}
