import Foundation

enum SloppyTUIAttachmentContext {
    static let imagePathExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "heic", "tif", "tiff"
    ]

    static func isImagePath(_ value: String) -> Bool {
        let path = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return false }
        let url: URL
        if path.hasPrefix("file://"), let parsed = URL(string: path.removingPercentEncoding ?? path) {
            url = parsed
        } else {
            url = URL(fileURLWithPath: path.removingPercentEncoding ?? path)
        }
        return imagePathExtensions.contains(url.pathExtension.lowercased())
    }

    static func imageMarker(filename: String) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "[Image]" : "[Image \(trimmed)]"
    }

    static func imageMarker(forPath path: String) -> String {
        let raw = path.removingPercentEncoding ?? path
        let url: URL
        if raw.hasPrefix("file://"), let parsed = URL(string: raw) {
            url = parsed
        } else {
            url = URL(fileURLWithPath: raw)
        }
        let filename = url.lastPathComponent.isEmpty ? (raw as NSString).lastPathComponent : url.lastPathComponent
        return imageMarker(filename: filename)
    }

    static func fileReferenceBlock(
        displayPath: String,
        absolutePath: String,
        sizeBytes: Int?
    ) -> String {
        var lines = [
            "[Attached file: \(displayPath)]",
            "Path: \(absolutePath)",
        ]
        if displayPath != absolutePath {
            lines.append("Project path: \(displayPath)")
        }
        if let sizeBytes {
            lines.append("Size: \(sizeBytes) bytes")
        } else {
            lines.append("Size: unknown")
        }
        lines.append("Content not inlined. Use `files.read` or `files.grep` with the path above if content is needed.")
        return lines.joined(separator: "\n")
    }
}
