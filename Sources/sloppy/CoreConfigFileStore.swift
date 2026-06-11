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

    static func numberedBackupPath(for path: String, index: Int) -> String {
        "\(backupPath(for: path)).\(index)"
    }

    static func hasConfigOrBackup(at path: String, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: path) ||
            !backupCandidates(for: path, fileManager: fileManager).isEmpty
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
        let backupURLs = backupCandidates(for: resolvedPath, fileManager: fileManager)
        let backupExists = !backupURLs.isEmpty

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
                if let restored = try restoreFirstValidBackup(
                    backupURLs,
                    to: configURL,
                    fileManager: fileManager
                ) {
                    return CoreConfigFileLoadResult(
                        config: restored.config,
                        path: configURL.path,
                        backupPath: restored.backupURL.path,
                        restoredFromBackup: true,
                        initializedFromDefault: false
                    )
                } else {
                    throw CoreConfigFileError.invalidPrimaryAndBackup(
                        path: configURL.path,
                        backupPath: backupURL.path,
                        primaryReason: primaryReason,
                        backupReason: "No valid backup found."
                    )
                }
            }
        }

        if backupExists {
            if let restored = try restoreFirstValidBackup(
                backupURLs,
                to: configURL,
                fileManager: fileManager
            ) {
                return CoreConfigFileLoadResult(
                    config: restored.config,
                    path: configURL.path,
                    backupPath: restored.backupURL.path,
                    restoredFromBackup: true,
                    initializedFromDefault: false
                )
            }

            throw CoreConfigFileError.invalidBackup(
                path: configURL.path,
                backupPath: backupURL.path,
                reason: "No valid backup found."
            )
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
            let nextBackupURL = nextNumberedBackupURL(for: configURL.path, fileManager: fileManager)
            try fileManager.createDirectory(
                at: nextBackupURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try decoded.data.write(to: nextBackupURL, options: .atomic)
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

    private static func backupCandidates(for path: String, fileManager: FileManager) -> [URL] {
        let legacyBackupPath = backupPath(for: path)
        let configURL = URL(fileURLWithPath: path)
        let directoryURL = configURL.deletingLastPathComponent()
        let fileName = configURL.lastPathComponent
        let numberedPrefix = "\(fileName).backup."
        let numberedBackups: [(index: Int, url: URL)]

        do {
            numberedBackups = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            )
            .compactMap { url in
                let name = url.lastPathComponent
                guard name.hasPrefix(numberedPrefix) else {
                    return nil
                }
                let suffix = name.dropFirst(numberedPrefix.count)
                guard let index = Int(suffix), index > 0 else {
                    return nil
                }
                return (index, url)
            }
        } catch {
            numberedBackups = []
        }

        var candidates = numberedBackups
            .sorted { $0.index > $1.index }
            .map(\.url)
        if fileManager.fileExists(atPath: legacyBackupPath) {
            candidates.append(URL(fileURLWithPath: legacyBackupPath))
        }
        return candidates
    }

    private static func nextNumberedBackupURL(for path: String, fileManager: FileManager) -> URL {
        var index = 1
        while fileManager.fileExists(atPath: numberedBackupPath(for: path, index: index)) {
            index += 1
        }
        return URL(fileURLWithPath: numberedBackupPath(for: path, index: index))
    }

    private static func restoreFirstValidBackup(
        _ backupURLs: [URL],
        to configURL: URL,
        fileManager: FileManager
    ) throws -> (config: CoreConfig, backupURL: URL)? {
        for backupURL in backupURLs {
            do {
                let decodedBackup = try decodeConfig(at: backupURL)
                try restoreBackup(from: backupURL, to: configURL, fileManager: fileManager)
                return (decodedBackup.config, backupURL)
            } catch let restoreError as CoreConfigFileError {
                throw restoreError
            } catch {
                continue
            }
        }
        return nil
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
