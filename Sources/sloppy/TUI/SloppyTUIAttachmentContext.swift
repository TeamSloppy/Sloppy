enum SloppyTUIAttachmentContext {
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
