import Darwin
import Foundation

/// Whether file I/O was a read or write, for tailored messages and codes.
enum FileSystemToolOperation: Sendable, Equatable {
    case read
    case write
}

/// Maps Foundation / POSIX file errors into stable tool error fields.
enum FileSystemToolErrorMapping {
    static func describe(error: Error, operation: FileSystemToolOperation, path: String) -> (
        code: String,
        message: String,
        retryable: Bool,
        hint: String?
    ) {
        if let cocoa = error as? CocoaError {
            return describeCocoa(cocoa, operation: operation, path: path)
        }

        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain {
            return describePOSIX(code: ns.code, operation: operation, path: path)
        }

        if ns.domain == NSCocoaErrorDomain {
            let cocoaCode = CocoaError.Code(rawValue: ns.code)
            return describeCocoa(CocoaError(cocoaCode), operation: operation, path: path)
        }

        return fallback(operation: operation, path: path)
    }

    // MARK: - Cocoa

    private static func describeCocoa(_ cocoa: CocoaError, operation: FileSystemToolOperation, path: String) -> (
        code: String,
        message: String,
        retryable: Bool,
        hint: String?
    ) {
        switch cocoa.code {
        case .fileNoSuchFile, .fileReadNoSuchFile:
            return notFound(operation: operation, path: path)
        case .fileReadNoPermission:
            return (
                "permission_denied",
                "Permission denied when reading \(path).",
                false,
                "Check file permissions and ownership, or choose a readable path."
            )
        case .fileWriteNoPermission:
            return (
                "permission_denied",
                "Permission denied when writing \(path).",
                false,
                "Check directory and file permissions, or choose a writable path."
            )
        case .fileWriteVolumeReadOnly:
            return (
                "volume_read_only",
                "The volume containing \(path) is read-only.",
                false,
                "Choose a writable location or adjust volume mount options."
            )
        case .fileWriteOutOfSpace:
            return (
                "disk_full",
                "Not enough disk space to write to \(path).",
                true,
                "Free disk space or write to a different volume."
            )
        case .fileReadCorruptFile:
            return (
                "read_failed",
                "The file at \(path) appears corrupted or unreadable.",
                false,
                "Replace the file or read a backup copy if available."
            )
        default:
            return describeCocoaNumeric(cocoa.code.rawValue, operation: operation, path: path)
        }
    }

    /// Fallback for Cocoa domain codes not represented in `CocoaError.Code`.
    private static func describeCocoaNumeric(_ code: Int, operation: FileSystemToolOperation, path: String) -> (
        code: String,
        message: String,
        retryable: Bool,
        hint: String?
    ) {
        switch code {
        case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
            return notFound(operation: operation, path: path)
        case NSFileReadNoPermissionError:
            return (
                "permission_denied",
                "Permission denied when reading \(path).",
                false,
                "Check file permissions and ownership, or choose a readable path."
            )
        case NSFileWriteNoPermissionError:
            return (
                "permission_denied",
                "Permission denied when writing \(path).",
                false,
                "Check directory and file permissions, or choose a writable path."
            )
        case NSFileWriteVolumeReadOnlyError:
            return (
                "volume_read_only",
                "The volume containing \(path) is read-only.",
                false,
                "Choose a writable location or adjust volume mount options."
            )
        case NSFileWriteOutOfSpaceError:
            return (
                "disk_full",
                "Not enough disk space to write to \(path).",
                true,
                "Free disk space or write to a different volume."
            )
        default:
            return fallback(operation: operation, path: path)
        }
    }

    // MARK: - POSIX

    private static func describePOSIX(code: Int, operation: FileSystemToolOperation, path: String) -> (
        code: String,
        message: String,
        retryable: Bool,
        hint: String?
    ) {
        switch code {
        case Int(ENOENT):
            return notFound(operation: operation, path: path)
        case Int(EACCES), Int(EPERM):
            let msg: String
            let hint: String
            switch operation {
            case .read:
                msg = "Permission denied when reading \(path)."
                hint = "Check file permissions and ownership, or choose a readable path."
            case .write:
                msg = "Permission denied when writing \(path)."
                hint = "Check directory and file permissions, or choose a writable path."
            }
            return ("permission_denied", msg, false, hint)
        case Int(EISDIR):
            return isDirectory(operation: operation, path: path)
        case Int(ENOSPC):
            return (
                "disk_full",
                "Not enough disk space to write to \(path).",
                true,
                "Free disk space or write to a different volume."
            )
        case Int(EROFS):
            return (
                "volume_read_only",
                "The volume containing \(path) is read-only.",
                false,
                "Choose a writable location or adjust volume mount options."
            )
        default:
            return fallback(operation: operation, path: path)
        }
    }

    // MARK: - Shared builders

    private static func notFound(operation: FileSystemToolOperation, path: String) -> (
        code: String,
        message: String,
        retryable: Bool,
        hint: String?
    ) {
        switch operation {
        case .read:
            return (
                "not_found",
                "No file at \(path).",
                false,
                "Confirm the path spelling and that the file exists under the workspace."
            )
        case .write:
            return (
                "not_found",
                "Could not write to \(path); the file or a parent directory may be missing.",
                false,
                "Create parent directories or fix the path."
            )
        }
    }

    /// Use when tools detect an existing path is a directory (e.g. via `fileExists(isDirectory:)`).
    static func describePathIsDirectory(operation: FileSystemToolOperation, path: String) -> (
        code: String,
        message: String,
        retryable: Bool,
        hint: String?
    ) {
        isDirectory(operation: operation, path: path)
    }

    private static func isDirectory(operation: FileSystemToolOperation, path: String) -> (
        code: String,
        message: String,
        retryable: Bool,
        hint: String?
    ) {
        switch operation {
        case .read:
            return (
                "is_directory",
                "\(path) is a directory, not a file.",
                false,
                "List the directory contents or open a file inside it."
            )
        case .write:
            return (
                "is_directory",
                "Cannot write file at \(path) because it is a directory.",
                false,
                "Choose a file path or remove the conflicting directory."
            )
        }
    }

    private static func fallback(operation: FileSystemToolOperation, path: String) -> (
        code: String,
        message: String,
        retryable: Bool,
        hint: String?
    ) {
        switch operation {
        case .read:
            return (
                "read_failed",
                "Could not read \(path).",
                true,
                "Retry if the failure may be transient; otherwise verify the path, permissions, and that the path points to a file."
            )
        case .write:
            return (
                "write_failed",
                "Could not write \(path).",
                true,
                "Retry if the failure may be transient; otherwise verify permissions, disk space, and parent directories."
            )
        }
    }
}
