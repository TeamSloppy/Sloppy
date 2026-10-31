import Foundation
import SloppyClientCore

enum MobileConnectionFailure {
    static func invalidatesSavedSession(_ error: any Error) -> Bool {
        let status = (error as? APIError)?.statusCode
        return status == 401 || status == 403
    }
}

@MainActor
enum MobileConnectionRetryLoop {
    enum AttemptResult {
        case idle
        case retry
    }

    static func run(
        attempt: () async -> AttemptResult,
        wait: (Int) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) async {
        var delay = 2
        while !Task.isCancelled {
            let result = await attempt()
            guard !Task.isCancelled else { return }
            if case .idle = result { delay = 2 }
            do { try await wait(delay) } catch { return }
            if case .retry = result { delay = min(30, delay * 2) }
        }
    }
}

struct MobileConnectionRecovery {
    private var wasBackgrounded = false

    mutating func didEnterBackground() {
        wasBackgrounded = true
    }

    mutating func consumeForegroundRecovery() -> Bool {
        defer { wasBackgrounded = false }
        return wasBackgrounded
    }

    static func shouldRestore(state: AppState, setupRequested: Bool) -> Bool {
        !setupRequested && (state == .splash || state == .connectionSetup)
    }
}
