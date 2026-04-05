import Foundation
import Testing
@testable import AgentRuntime
@testable import Protocols

@Test
func workerRuntimeUsesInjectedExecutorForExecution() async {
    let runtime = WorkerRuntime(
        eventBus: EventBus(),
        executor: CompletingWorkerExecutor(summary: "custom-summary")
    )
    let spec = WorkerTaskSpec(
        taskId: "task-executor",
        channelId: "general",
        title: "Injected",
        objective: "do work",
        tools: ["shell"],
        mode: .fireAndForget
    )

    let workerId = await runtime.spawn(spec: spec, autoStart: false)
    await runtime.execute(workerId: workerId)

    let snapshot = await runtime.snapshot(workerId: workerId)
    #expect(snapshot?.status == .completed)
    #expect(snapshot?.latestReport == "custom-summary")
}

@Test
func workerRuntimeCanHotSwapExecutorBeforeExecution() async {
    let runtime = WorkerRuntime(eventBus: EventBus())
    let spec = WorkerTaskSpec(
        taskId: "task-hot-swap",
        channelId: "general",
        title: "Swap",
        objective: "fallback objective",
        tools: ["shell"],
        mode: .fireAndForget
    )

    let workerId = await runtime.spawn(spec: spec, autoStart: false)
    await runtime.updateExecutor(CompletingWorkerExecutor(summary: "hot-swapped-summary"))
    await runtime.execute(workerId: workerId)

    let snapshot = await runtime.snapshot(workerId: workerId)
    #expect(snapshot?.status == .completed)
    #expect(snapshot?.latestReport == "hot-swapped-summary")
}

@Test
func workerRuntimeMarksWorkerFailedWhenExecutorThrows() async {
    let runtime = WorkerRuntime(
        eventBus: EventBus(),
        executor: ThrowingExecuteWorkerExecutor()
    )
    let spec = WorkerTaskSpec(
        taskId: "task-error",
        channelId: "general",
        title: "Error path",
        objective: "do work",
        tools: ["shell"],
        mode: .fireAndForget
    )

    let workerId = await runtime.spawn(spec: spec, autoStart: false)
    await runtime.execute(workerId: workerId)

    let snapshot = await runtime.snapshot(workerId: workerId)
    #expect(snapshot?.status == .failed)
    #expect(snapshot?.latestReport?.contains("Fire-and-forget execution failed") == true)
    #expect(snapshot?.latestReport?.contains("injected execute failure") == true)
}

@Test
func workerRuntimeMarksWorkerFailedWhenRouteExecutorThrows() async {
    let runtime = WorkerRuntime(
        eventBus: EventBus(),
        executor: ThrowingRouteWorkerExecutor()
    )
    let spec = WorkerTaskSpec(
        taskId: "task-route-error",
        channelId: "general",
        title: "Route error",
        objective: "wait for route",
        tools: ["shell"],
        mode: .interactive
    )

    let workerId = await runtime.spawn(spec: spec, autoStart: false)
    await runtime.execute(workerId: workerId)

    let routeResult = await runtime.route(workerId: workerId, message: "continue")
    let snapshot = await runtime.snapshot(workerId: workerId)

    #expect(routeResult.accepted)
    #expect(routeResult.completed)
    #expect(snapshot?.status == .failed)
    #expect(snapshot?.latestReport?.contains("Interactive route failed") == true)
    #expect(snapshot?.latestReport?.contains("injected route failure") == true)
}

@Test
func workerRuntimeCompleteNowIgnoredWhenAlreadyFailed() async {
    let runtime = WorkerRuntime(eventBus: EventBus())
    let spec = WorkerTaskSpec(
        taskId: "task-guard-fail",
        channelId: "general",
        title: "Guard",
        objective: "guard test",
        tools: [],
        mode: .fireAndForget
    )
    let workerId = await runtime.spawn(spec: spec, autoStart: false)
    await runtime.fail(workerId: workerId, error: "timed out")
    let ref = await runtime.completeNow(workerId: workerId, summary: "late result")
    let snapshot = await runtime.snapshot(workerId: workerId)
    #expect(ref == nil)
    #expect(snapshot?.status == .failed)
    #expect(snapshot?.latestReport == "timed out")
}

@Test
func workerRuntimeFailIgnoredWhenAlreadyCompleted() async {
    let runtime = WorkerRuntime(
        eventBus: EventBus(),
        executor: CompletingWorkerExecutor(summary: "done")
    )
    let spec = WorkerTaskSpec(
        taskId: "task-guard-complete",
        channelId: "general",
        title: "Guard",
        objective: "guard test",
        tools: [],
        mode: .fireAndForget
    )
    let workerId = await runtime.spawn(spec: spec, autoStart: false)
    await runtime.execute(workerId: workerId)
    await runtime.fail(workerId: workerId, error: "late failure")
    let snapshot = await runtime.snapshot(workerId: workerId)
    #expect(snapshot?.status == .completed)
    #expect(snapshot?.latestReport == "done")
}

private struct CompletingWorkerExecutor: WorkerExecutor {
    let summary: String

    func execute(workerId: String, spec: WorkerTaskSpec) async throws -> WorkerExecutionResult {
        .completed(summary: summary)
    }

    func route(workerId: String, spec: WorkerTaskSpec, message: String) async throws -> WorkerRouteExecutionResult {
        .waitingForRoute(report: nil)
    }

    func cancel(workerId: String, spec: WorkerTaskSpec) async {}
}

private struct ThrowingExecuteWorkerExecutor: WorkerExecutor {
    func execute(workerId: String, spec: WorkerTaskSpec) async throws -> WorkerExecutionResult {
        throw ExecutorTestError.executeFailure
    }

    func route(workerId: String, spec: WorkerTaskSpec, message: String) async throws -> WorkerRouteExecutionResult {
        .waitingForRoute(report: nil)
    }

    func cancel(workerId: String, spec: WorkerTaskSpec) async {}
}

private struct ThrowingRouteWorkerExecutor: WorkerExecutor {
    func execute(workerId: String, spec: WorkerTaskSpec) async throws -> WorkerExecutionResult {
        .waitingForRoute(report: "waiting_for_route")
    }

    func route(workerId: String, spec: WorkerTaskSpec, message: String) async throws -> WorkerRouteExecutionResult {
        throw ExecutorTestError.routeFailure
    }

    func cancel(workerId: String, spec: WorkerTaskSpec) async {}
}

private enum ExecutorTestError: LocalizedError {
    case executeFailure
    case routeFailure

    var errorDescription: String? {
        switch self {
        case .executeFailure:
            return "injected execute failure"
        case .routeFailure:
            return "injected route failure"
        }
    }
}
