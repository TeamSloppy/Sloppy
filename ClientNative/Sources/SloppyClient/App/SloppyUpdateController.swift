#if os(macOS)
import AppKit
import Foundation

#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class SloppyUpdateController {
    static let shared = SloppyUpdateController()

    #if canImport(Sparkle)
    private var updaterController: SPUStandardUpdaterController?
    #endif
    private var startupError: String?

    private init() {}

    func start() {
        #if canImport(Sparkle)
        guard updaterController == nil else { return }
        guard Self.hasValidConfiguration else {
            startupError = "This build does not have a signed update channel configured."
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller
        do {
            try controller.updater.start()
        } catch {
            startupError = error.localizedDescription
        }
        #else
        startupError = "Updates are unavailable in this development build."
        #endif
    }

    func checkForUpdates() {
        start()
        #if canImport(Sparkle)
        if let updaterController, startupError == nil {
            updaterController.checkForUpdates(nil)
            return
        }
        #endif
        showUnavailableAlert()
    }

    #if canImport(Sparkle)
    private static var hasValidConfiguration: Bool {
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let feedURL = URL(string: feed),
              feedURL.scheme == "https",
              feedURL.host != nil,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else {
            return false
        }
        return true
    }
    #endif

    private func showUnavailableAlert() {
        let alert = NSAlert()
        alert.messageText = "Unable to Check for Updates"
        alert.informativeText = startupError ?? "Please try again later."
        alert.runModal()
    }
}
#endif
