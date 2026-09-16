import Foundation

func mainViewAwareSourceContents(at sourceURL: URL) throws -> String {
    guard sourceURL.lastPathComponent == "MainView.swift" else {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    let directoryURL = sourceURL.deletingLastPathComponent()
    let sourceURLs = try FileManager.default.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: nil
    )
        .filter { url in
            let name = url.lastPathComponent
            return name == "MainView.swift"
                || name == "MainViewComponents.swift"
                || (name.hasPrefix("MainView+") && name.hasSuffix(".swift"))
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    return try sourceURLs
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined(separator: "\n")
}

