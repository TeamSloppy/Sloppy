import Foundation

enum OpenCodeConfigImporter {
    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var cache: [String: [CoreConfig.ModelConfig]] = [:]

    static func importedModelConfigs(
        settings: CoreConfig.OpenCode,
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) -> [CoreConfig.ModelConfig] {
        guard settings.enabled else { return [] }

        let key = cacheKey(settings: settings, currentDirectory: currentDirectory)
        cacheLock.lock()
        if let cached = cache[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let config = loadResolvedConfig(settings: settings, currentDirectory: currentDirectory)
            ?? loadMergedFileConfig(settings: settings, currentDirectory: currentDirectory)
        let imported = config.map { parseModelConfigs(from: $0, settings: settings) } ?? []

        cacheLock.lock()
        cache[key] = imported
        cacheLock.unlock()
        return imported
    }

    static func parseModelConfigs(
        from config: [String: Any],
        settings: CoreConfig.OpenCode = .init(enabled: true)
    ) -> [CoreConfig.ModelConfig] {
        guard let providers = config["provider"] as? [String: Any] else { return [] }

        let includes = Set(settings.includeProviders)
        let excludes = Set(settings.excludeProviders)
        var models: [CoreConfig.ModelConfig] = []

        for providerID in providers.keys.sorted() {
            guard includes.isEmpty || includes.contains(providerID) else { continue }
            guard !excludes.contains(providerID) else { continue }
            guard let provider = providers[providerID] as? [String: Any] else { continue }
            guard let providerModels = provider["models"] as? [String: Any] else { continue }

            guard let providerNPM = stringValue(provider["npm"]),
                  isSupportedNPMPackage(providerNPM)
            else { continue }

            let providerName = stringValue(provider["name"]) ?? providerID
            let options = provider["options"] as? [String: Any] ?? [:]
            guard let baseURL = firstString(options, keys: ["baseURL", "baseUrl", "endpoint"]) else { continue }
            let apiKey = stringValue(options["apiKey"]) ?? ""
            let usesResponses = providerNPM == "@ai-sdk/openai"

            for modelID in providerModels.keys.sorted() {
                let rawModel = providerModels[modelID]
                let model = rawModel as? [String: Any] ?? [:]
                let modelNPM = stringValue(model["npm"]) ?? providerNPM
                guard isSupportedNPMPackage(modelNPM) else { continue }

                let displayName = stringValue(model["name"]) ?? modelID
                let catalogSuffix = usesResponses || modelNPM == "@ai-sdk/openai" ? "|responses" : ""
                models.append(
                    CoreConfig.ModelConfig(
                        title: "opencode:\(providerName) / \(displayName)",
                        apiKey: apiKey,
                        apiUrl: baseURL,
                        model: "opencode:\(providerID)/\(modelID)",
                        providerCatalogId: "opencode:\(providerID)\(catalogSuffix)"
                    )
                )
            }
        }

        return models
    }

    private static func loadResolvedConfig(
        settings: CoreConfig.OpenCode,
        currentDirectory: String
    ) -> [String: Any]? {
        guard settings.useResolvedConfigCommand else { return nil }
        let command = settings.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return nil }

        let process = Process()
        if command.contains("/") {
            process.executableURL = URL(fileURLWithPath: expandPath(command))
            process.arguments = ["debug", "config"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command, "debug", "config"]
        }
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory, isDirectory: true)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-opencode-config-\(UUID().uuidString).json")
        let errorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-opencode-config-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        guard let outputHandle = try? FileHandle(forWritingTo: outputURL),
              let errorHandle = try? FileHandle(forWritingTo: errorURL)
        else {
            return nil
        }
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        do {
            try process.run()
        } catch {
            return nil
        }

        let timeout = DispatchTime.now() + .milliseconds(max(1, settings.timeoutMs))
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        if semaphore.wait(timeout: timeout) == .timedOut {
            process.terminate()
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        return decodeJSONObject(from: data)
    }

    private static func loadMergedFileConfig(
        settings: CoreConfig.OpenCode,
        currentDirectory: String
    ) -> [String: Any]? {
        var merged: [String: Any] = [:]
        var loadedAny = false
        for path in defaultConfigPaths(currentDirectory: currentDirectory) + settings.configPaths {
            let expanded = expandPath(path, currentDirectory: currentDirectory)
            let url = URL(fileURLWithPath: expanded)
            guard let data = try? Data(contentsOf: url),
                  let object = decodeJSONObject(from: data)
            else { continue }
            merged = merge(base: merged, override: object)
            loadedAny = true
        }
        return loadedAny ? merged : nil
    }

    private static func defaultConfigPaths(currentDirectory: String) -> [String] {
        var paths: [String] = [
            "~/.config/opencode/opencode.json",
            "~/.config/opencode/opencode.jsonc",
        ]

        if let custom = ProcessInfo.processInfo.environment["OPENCODE_CONFIG"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty
        {
            paths.append(custom)
        }

        if let project = nearestProjectConfig(currentDirectory: currentDirectory) {
            paths.append(project)
        }
        return paths
    }

    private static func nearestProjectConfig(currentDirectory: String) -> String? {
        var url = URL(fileURLWithPath: currentDirectory, isDirectory: true).standardizedFileURL
        while true {
            for name in ["opencode.json", "opencode.jsonc"] {
                let candidate = url.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate.path
                }
            }
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
                return nil
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return nil }
            url = parent
        }
    }

    private static func decodeJSONObject(from data: Data) -> [String: Any]? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let normalized = stripJSONC(from: text)
        guard let normalizedData = normalized.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: normalizedData)) as? [String: Any]
    }

    private static func stripJSONC(from text: String) -> String {
        enum State {
            case normal
            case string
            case lineComment
            case blockComment
        }

        var state = State.normal
        var result = ""
        var previous: Character?
        var iterator = text.makeIterator()
        var pending: Character?

        func nextCharacter() -> Character? {
            if let value = pending {
                pending = nil
                return value
            }
            return iterator.next()
        }

        while let char = nextCharacter() {
            switch state {
            case .normal:
                if char == "\"" {
                    state = .string
                    result.append(char)
                } else if char == "/" {
                    guard let next = nextCharacter() else {
                        result.append(char)
                        break
                    }
                    if next == "/" {
                        state = .lineComment
                    } else if next == "*" {
                        state = .blockComment
                    } else {
                        result.append(char)
                        pending = next
                    }
                } else {
                    result.append(char)
                }
            case .string:
                result.append(char)
                if char == "\"", previous != "\\" {
                    state = .normal
                }
            case .lineComment:
                if char == "\n" {
                    state = .normal
                    result.append(char)
                }
            case .blockComment:
                if previous == "*", char == "/" {
                    state = .normal
                }
            }
            previous = char
        }

        return removeTrailingCommas(from: result)
    }

    private static func removeTrailingCommas(from text: String) -> String {
        text.replacingOccurrences(
            of: #",\s*([}\]])"#,
            with: "$1",
            options: .regularExpression
        )
    }

    private static func merge(base: [String: Any], override: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in override {
            if let baseObject = result[key] as? [String: Any],
               let overrideObject = value as? [String: Any]
            {
                result[key] = merge(base: baseObject, override: overrideObject)
            } else {
                result[key] = value
            }
        }
        return result
    }

    private static func isSupportedNPMPackage(_ value: String) -> Bool {
        value == "@ai-sdk/openai-compatible" || value == "@ai-sdk/openai"
    }

    private static func firstString(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = stringValue(object[key]), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func expandPath(
        _ raw: String,
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let home = CoreConfig.resolvedHomeDirectoryPath()
        if trimmed == "~" { return home }
        if trimmed.hasPrefix("~/") {
            return URL(fileURLWithPath: home)
                .appendingPathComponent(String(trimmed.dropFirst(2)))
                .path
        }
        if trimmed == "$HOME" { return home }
        if trimmed.hasPrefix("$HOME/") {
            return URL(fileURLWithPath: home)
                .appendingPathComponent(String(trimmed.dropFirst("$HOME/".count)))
                .path
        }
        if trimmed.hasPrefix("/") { return trimmed }
        return URL(fileURLWithPath: currentDirectory, isDirectory: true)
            .appendingPathComponent(trimmed)
            .standardizedFileURL
            .path
    }

    private static func cacheKey(settings: CoreConfig.OpenCode, currentDirectory: String) -> String {
        [
            currentDirectory,
            String(settings.enabled),
            String(settings.useResolvedConfigCommand),
            settings.command,
            settings.configPaths.joined(separator: "\u{1e}"),
            settings.authPath ?? "",
            settings.includeProviders.joined(separator: "\u{1e}"),
            settings.excludeProviders.joined(separator: "\u{1e}"),
            String(settings.timeoutMs),
            ProcessInfo.processInfo.environment["OPENCODE_CONFIG"] ?? "",
        ].joined(separator: "\u{1f}")
    }
}
