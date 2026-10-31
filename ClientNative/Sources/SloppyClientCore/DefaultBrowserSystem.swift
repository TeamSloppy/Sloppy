import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// The system owns the user's default browser choice and any consent prompts.
@MainActor
public enum DefaultBrowserSystem {
    #if os(macOS)
    public static var isDefault: Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        return ["http", "https"].allSatisfy { scheme in
            guard let url = URL(string: "\(scheme)://example.com"),
                  let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: url),
                  let handlerID = Bundle(url: applicationURL)?.bundleIdentifier else { return false }
            return bundleID.caseInsensitiveCompare(handlerID) == .orderedSame
        }
    }
    #endif

    public static func requestDefault() async throws {
        #if os(macOS)
        for scheme in ["http", "https"] {
            try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
        }
        #elseif os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString),
              await UIApplication.shared.open(url) else {
            throw CocoaError(.featureUnsupported)
        }
        #endif
    }
}
