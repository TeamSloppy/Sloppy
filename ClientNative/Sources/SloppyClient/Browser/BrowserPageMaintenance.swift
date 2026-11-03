import Foundation
import Dispatch
#if os(iOS)
import UIKit
#endif

/// Owns timers and OS subscriptions, never the browsing workspace itself.
@MainActor
final class BrowserPageMaintenance {
    private let timer: Task<Void, Never>
#if os(macOS)
    private let pressure: any DispatchSourceMemoryPressure
#elseif os(iOS)
    private let warnings: Task<Void, Never>
#endif

    init(state: BrowserWorkspaceState) {
        timer = Task { [weak state] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
                guard state != nil else { break }
                _ = await state?.discardInactivePages()
            }
        }
#if os(macOS)
        pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        pressure.setEventHandler { [weak state] in
            Task { @MainActor in _ = await state?.discardInactivePages(reason: .memoryPressure) }
        }
        pressure.resume()
#elseif os(iOS)
        warnings = Task { [weak state] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didReceiveMemoryWarningNotification).map({ _ in true }) {
                guard !Task.isCancelled, state != nil else { break }
                _ = await state?.discardInactivePages(reason: .memoryPressure)
            }
        }
#endif
    }

    deinit {
        timer.cancel()
#if os(macOS)
        pressure.cancel()
#elseif os(iOS)
        warnings.cancel()
#endif
    }
}

enum BrowserPageDiscardReason { case idle, memoryPressure }
