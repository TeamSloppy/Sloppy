import Foundation
import Testing
@testable import SloppyClientUI

@MainActor
struct MobileRefreshTests {
    @Test func cancellingTheGestureDoesNotCancelTheRequest() async {
        let runner = MobileRefreshRunner()
        let started = RefreshTestLatch()
        let finish = RefreshTestLatch()
        var completed = false
        var requestWasCancelled = false
        let caller = Task {
            await runner.run {
                await started.open()
                await finish.wait()
                requestWasCancelled = Task.isCancelled
                completed = true
            }
        }
        await started.wait()
        caller.cancel()
        await finish.open()
        await caller.value
        #expect(completed)
        #expect(!requestWasCancelled)
    }

    @Test func overlappingGesturesShareOneRequest() async {
        let runner = MobileRefreshRunner()
        let started = RefreshTestLatch()
        let finish = RefreshTestLatch()
        var calls = 0
        let first = Task {
            await runner.run {
                calls += 1
                await started.open()
                await finish.wait()
            }
        }
        await started.wait()
        let secondStarted = AsyncStream<Void>.makeStream()
        let second = Task {
            secondStarted.continuation.yield(())
            await runner.run { calls += 1 }
        }
        var events = secondStarted.stream.makeAsyncIterator()
        _ = await events.next()
        await finish.open()
        await first.value
        await second.value
        #expect(calls == 1)
    }

    @Test func leavingTheScreenCancelsTheRequest() async {
        let runner = MobileRefreshRunner()
        let started = RefreshTestLatch()
        var requestWasCancelled = false
        let caller = Task {
            await runner.run {
                await started.open()
                do { try await Task.sleep(for: .seconds(30)) }
                catch { requestWasCancelled = Task.isCancelled }
            }
        }
        await started.wait()
        runner.cancel()
        await caller.value
        #expect(requestWasCancelled)
    }
}

private actor RefreshTestLatch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters = []
        for waiter in pending { waiter.resume() }
    }
}
