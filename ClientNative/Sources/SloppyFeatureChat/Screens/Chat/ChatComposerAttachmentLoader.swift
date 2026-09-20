import Foundation
import UniformTypeIdentifiers

struct ChatComposerPreparedAttachment: Sendable, Equatable {
    let data: Data
    let name: String
    let mimeType: String
}

enum ChatComposerAttachmentLoadResult: Sendable, Equatable {
    case success(ChatComposerPreparedAttachment)
    case failure(String)
}

enum ChatComposerAttachmentLoader {
    enum LoaderError: LocalizedError, Equatable {
        case unreadable(String)
        case directoryTooLarge(String)
        case unsupportedArchiveEntry(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let name):
                "Could not read \(name)"
            case .directoryTooLarge(let name):
                "\(name) is too large to attach"
            case .unsupportedArchiveEntry(let name):
                "Could not archive \(name)"
            }
        }
    }

    static func load(
        url: URL,
        maximumSize: Int
    ) throws -> ChatComposerPreparedAttachment {
        let didAccessSecurityScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard values.isSymbolicLink != true else {
            throw LoaderError.unsupportedArchiveEntry(url.lastPathComponent)
        }

        if values.isDirectory == true {
            let archive = try ChatComposerZIPArchive.archiveDirectory(
                at: url,
                maximumSize: maximumSize
            )
            return ChatComposerPreparedAttachment(
                data: archive,
                name: archiveName(for: url),
                mimeType: UTType.zip.preferredMIMEType ?? "application/zip"
            )
        }

        guard values.isRegularFile == true else {
            throw LoaderError.unreadable(url.lastPathComponent)
        }
        guard (values.fileSize ?? 0) <= maximumSize else {
            throw LoaderError.directoryTooLarge(url.lastPathComponent)
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        return ChatComposerPreparedAttachment(
            data: data,
            name: url.lastPathComponent,
            mimeType: contentType?.preferredMIMEType
                ?? UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
        )
    }

    private static func archiveName(for directoryURL: URL) -> String {
        let name = directoryURL.lastPathComponent.isEmpty
            ? "Directory"
            : directoryURL.lastPathComponent
        return "\(name).zip"
    }
}

private enum ChatComposerZIPArchive {
    private struct Entry {
        let path: String
        let data: Data
        let isDirectory: Bool
        let modificationDate: Date
    }

    private struct CentralDirectoryEntry {
        let entry: Entry
        let crc32: UInt32
        let offset: UInt32
    }

    static func archiveDirectory(at directoryURL: URL, maximumSize: Int) throws -> Data {
        let entries = try entries(in: directoryURL, maximumSize: maximumSize)
        var archive = Data()
        var centralEntries: [CentralDirectoryEntry] = []

        for entry in entries {
            let pathData = Data(entry.path.utf8)
            let crc32 = entry.isDirectory ? 0 : CRC32.checksum(entry.data)
            guard archive.count <= Int(UInt32.max),
                  entry.data.count <= Int(UInt32.max),
                  pathData.count <= Int(UInt16.max) else {
                throw ChatComposerAttachmentLoader.LoaderError.directoryTooLarge(
                    directoryURL.lastPathComponent
                )
            }

            let offset = UInt32(archive.count)
            let (time, date) = dosTimestamp(for: entry.modificationDate)
            archive.appendLittleEndian(UInt32(0x04034b50))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(UInt16(0x0800))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(time)
            archive.appendLittleEndian(date)
            archive.appendLittleEndian(crc32)
            archive.appendLittleEndian(UInt32(entry.data.count))
            archive.appendLittleEndian(UInt32(entry.data.count))
            archive.appendLittleEndian(UInt16(pathData.count))
            archive.appendLittleEndian(UInt16(0))
            archive.append(pathData)
            archive.append(entry.data)
            try ensureSize(archive, maximumSize: maximumSize, name: directoryURL.lastPathComponent)

            centralEntries.append(
                CentralDirectoryEntry(entry: entry, crc32: crc32, offset: offset)
            )
        }

        guard archive.count <= Int(UInt32.max),
              centralEntries.count <= Int(UInt16.max) else {
            throw ChatComposerAttachmentLoader.LoaderError.directoryTooLarge(
                directoryURL.lastPathComponent
            )
        }
        let centralDirectoryOffset = UInt32(archive.count)

        for central in centralEntries {
            let entry = central.entry
            let pathData = Data(entry.path.utf8)
            let (time, date) = dosTimestamp(for: entry.modificationDate)
            archive.appendLittleEndian(UInt32(0x02014b50))
            archive.appendLittleEndian(UInt16(0x0314))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(UInt16(0x0800))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(time)
            archive.appendLittleEndian(date)
            archive.appendLittleEndian(central.crc32)
            archive.appendLittleEndian(UInt32(entry.data.count))
            archive.appendLittleEndian(UInt32(entry.data.count))
            archive.appendLittleEndian(UInt16(pathData.count))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(entry.isDirectory ? UInt32(0x10) : UInt32(0))
            archive.appendLittleEndian(central.offset)
            archive.append(pathData)
            try ensureSize(archive, maximumSize: maximumSize, name: directoryURL.lastPathComponent)
        }

        let centralDirectorySize = UInt32(archive.count) - centralDirectoryOffset
        archive.appendLittleEndian(UInt32(0x06054b50))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(centralEntries.count))
        archive.appendLittleEndian(UInt16(centralEntries.count))
        archive.appendLittleEndian(centralDirectorySize)
        archive.appendLittleEndian(centralDirectoryOffset)
        archive.appendLittleEndian(UInt16(0))
        try ensureSize(archive, maximumSize: maximumSize, name: directoryURL.lastPathComponent)
        return archive
    }

    private static func entries(in directoryURL: URL, maximumSize: Int) throws -> [Entry] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey,
            .fileSizeKey,
        ]
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw ChatComposerAttachmentLoader.LoaderError.unreadable(
                directoryURL.lastPathComponent
            )
        }

        var entries: [Entry] = []
        var estimatedArchiveSize = 22
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }

            let relativePath = relativePath(of: url, inside: directoryURL)
            let modificationDate = values.contentModificationDate ?? Date()
            if values.isDirectory == true {
                estimatedArchiveSize += 76 + relativePath.utf8.count + 1
                guard estimatedArchiveSize <= maximumSize else {
                    throw ChatComposerAttachmentLoader.LoaderError.directoryTooLarge(
                        directoryURL.lastPathComponent
                    )
                }
                entries.append(
                    Entry(
                        path: relativePath + "/",
                        data: Data(),
                        isDirectory: true,
                        modificationDate: modificationDate
                    )
                )
            } else if values.isRegularFile == true {
                estimatedArchiveSize += 76 + relativePath.utf8.count + (values.fileSize ?? 0)
                guard estimatedArchiveSize <= maximumSize else {
                    throw ChatComposerAttachmentLoader.LoaderError.directoryTooLarge(
                        directoryURL.lastPathComponent
                    )
                }
                entries.append(
                    Entry(
                        path: relativePath,
                        data: try Data(contentsOf: url, options: .mappedIfSafe),
                        isDirectory: false,
                        modificationDate: modificationDate
                    )
                )
            }
        }
        if let enumerationError {
            throw enumerationError
        }
        return entries.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func relativePath(of url: URL, inside directoryURL: URL) -> String {
        let rootPath = directoryURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let start = path.index(path.startIndex, offsetBy: min(rootPath.count, path.count))
        return String(path[start...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func dosTimestamp(for date: Date) -> (UInt16, UInt16) {
        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone.current,
            from: date
        )
        let year = min(max(components.year ?? 1980, 1980), 2107)
        let month = min(max(components.month ?? 1, 1), 12)
        let day = min(max(components.day ?? 1, 1), 31)
        let hour = min(max(components.hour ?? 0, 0), 23)
        let minute = min(max(components.minute ?? 0, 0), 59)
        let second = min(max(components.second ?? 0, 0), 59)
        let time = UInt16((hour << 11) | (minute << 5) | (second / 2))
        let date = UInt16(((year - 1980) << 9) | (month << 5) | day)
        return (time, date)
    }

    private static func ensureSize(_ data: Data, maximumSize: Int, name: String) throws {
        guard data.count <= maximumSize else {
            throw ChatComposerAttachmentLoader.LoaderError.directoryTooLarge(name)
        }
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc & 1) == 1
                ? 0xEDB88320 ^ (crc >> 1)
                : crc >> 1
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ UInt32.max
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
