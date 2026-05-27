import Foundation

struct CoreConfigFileLoadResult {
    var config: CoreConfig
    var path: String
    var backupPath: String
    var restoredFromBackup: Bool
    var initializedFromDefault: Bool
}

enum CoreConfigFileError: Error, LocalizedError {
    case invalidPrimary(path: String, backupPath: String, reason: String)
    case invalidPrimaryAndBackup(path: String, backupPath: String, primaryReason: String, backupReason: String)
    case invalidBackup(path: String, backupPath: String, reason: String)
    case restoreFailed(path: String, backupPath: String, reason: String)
    case backupFailed(path: String, backupPath: String, reason: String)

    var errorDescription: String? {
        switch self {
        case let .invalidPrimary(path, backupPath, reason):
            return "Config file at \(path) is invalid and no usable backup exists at \(backupPath): \(reason)"
        case let .invalidPrimaryAndBackup(path, backupPath, primaryReason, backupReason):
            return "Config file at \(path) is invalid (\(primaryReason)); backup at \(backupPath) is also invalid (\(backupReason))."
        case let .invalidBackup(path, backupPath, reason):
            return "Config file at \(path) is missing and backup at \(backupPath) is invalid: \(reason)"
        case let .restoreFailed(path, backupPath, reason):
            return "Could not restore config file at \(path) from backup \(backupPath): \(reason)"
        case let .backupFailed(path, backupPath, reason):
            return "Could not back up config file at \(path) to \(backupPath): \(reason)"
        }
    }
}

enum CoreConfigFileStore {
    static func backupPath(for path: String) -> String {
        "\(path).backup"
    }

    static func hasConfigOrBackup(at path: String, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: path) ||
            fileManager.fileExists(atPath: backupPath(for: path))
    }

    static func loadRecovering(
        path: String,
        currentDirectory: String = FileManager.default.currentDirectoryPath,
        fileManager: FileManager = .default
    ) throws -> CoreConfigFileLoadResult {
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPath = normalizedPath.isEmpty
            ? CoreConfig.defaultConfigPath(currentDirectory: currentDirectory)
            : normalizedPath
        let configURL = URL(fileURLWithPath: resolvedPath)
        let backupPath = backupPath(for: resolvedPath)
        let backupURL = URL(fileURLWithPath: backupPath)
        let primaryExists = fileManager.fileExists(atPath: configURL.path)
        let backupExists = fileManager.fileExists(atPath: backupURL.path)

        if primaryExists {
            do {
                let decoded = try decodeConfig(at: configURL)
                return CoreConfigFileLoadResult(
                    config: decoded.config,
                    path: configURL.path,
                    backupPath: backupURL.path,
                    restoredFromBackup: false,
                    initializedFromDefault: false
                )
            } catch {
                guard backupExists else {
                    throw CoreConfigFileError.invalidPrimary(
                        path: configURL.path,
                        backupPath: backupURL.path,
                        reason: describe(error)
                    )
                }

                let primaryReason = describe(error)
                do {
                    let decodedBackup = try decodeConfig(at: backupURL)
                    try restoreBackup(from: backupURL, to: configURL, fileManager: fileManager)
                    return CoreConfigFileLoadResult(
                        config: decodedBackup.config,
                        path: configURL.path,
                        backupPath: backupURL.path,
                        restoredFromBackup: true,
                        initializedFromDefault: false
                    )
                } catch let restoreError as CoreConfigFileError {
                    throw restoreError
                } catch {
                    throw CoreConfigFileError.invalidPrimaryAndBackup(
                        path: configURL.path,
                        backupPath: backupURL.path,
                        primaryReason: primaryReason,
                        backupReason: describe(error)
                    )
                }
            }
        }

        if backupExists {
            do {
                let decodedBackup = try decodeConfig(at: backupURL)
                try restoreBackup(from: backupURL, to: configURL, fileManager: fileManager)
                return CoreConfigFileLoadResult(
                    config: decodedBackup.config,
                    path: configURL.path,
                    backupPath: backupURL.path,
                    restoredFromBackup: true,
                    initializedFromDefault: false
                )
            } catch let restoreError as CoreConfigFileError {
                throw restoreError
            } catch {
                throw CoreConfigFileError.invalidBackup(
                    path: configURL.path,
                    backupPath: backupURL.path,
                    reason: describe(error)
                )
            }
        }

        return CoreConfigFileLoadResult(
            config: .default,
            path: configURL.path,
            backupPath: backupURL.path,
            restoredFromBackup: false,
            initializedFromDefault: true
        )
    }

    static func backupExistingConfigIfValid(
        path: String,
        fileManager: FileManager = .default
    ) throws {
        let configURL = URL(fileURLWithPath: path)
        guard fileManager.fileExists(atPath: configURL.path) else {
            return
        }

        let backupURL = URL(fileURLWithPath: backupPath(for: configURL.path))
        do {
            let decoded = try decodeConfig(at: configURL)
            try fileManager.createDirectory(
                at: backupURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try decoded.data.write(to: backupURL, options: .atomic)
        } catch {
            throw CoreConfigFileError.backupFailed(
                path: configURL.path,
                backupPath: backupURL.path,
                reason: describe(error)
            )
        }
    }

    private static func decodeConfig(at url: URL) throws -> (config: CoreConfig, data: Data) {
        let data = try Data(contentsOf: url)
        let config = try JSONDecoder().decode(CoreConfig.self, from: data)
        return (config, data)
    }

    private static func restoreBackup(
        from backupURL: URL,
        to configURL: URL,
        fileManager: FileManager
    ) throws {
        do {
            try fileManager.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try Data(contentsOf: backupURL)
            try data.write(to: configURL, options: .atomic)
        } catch {
            throw CoreConfigFileError.restoreFailed(
                path: configURL.path,
                backupPath: backupURL.path,
                reason: describe(error)
            )
        }
    }

    private static func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription
        {
            return description
        }
        return String(describing: error)
    }
}
