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
    static func run(
        attempt: () async -> Void,
        wait: (Int) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) async {
        var delay = 2
        while !Task.isCancelled {
            await attempt()
            guard !Task.isCancelled else { return }
            do { try await wait(delay) } catch { return }
            delay = min(30, delay * 2)
        }
    }
}
