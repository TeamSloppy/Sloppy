import Foundation
#if canImport(AppKit)
import AppKit
#endif
import ChannelPluginSupport
import Logging
import Protocols
import TauTUI

@MainActor
extension SloppyTUIScreen {
    func stopTUI(reason: String) async {
        guard !isExiting else {
            return
        }
        isExiting = true
        await interruptCurrentRunForExit(reason: reason)
        let summary = await makeExitSummary(now: Date())
        printExitSummary(summary)
        onExit?()
    }

    func makeExitSummary(now: Date) async -> SloppyTUIExitSummary {
        let detail = hasPersistedSession
            ? try? await service.getAgentSession(agentID: agent.id, sessionID: session.id)
            : nil
        let events = detail?.events.filter { $0.createdAt >= tuiStartedAt } ?? []
        let resultEvents = events.compactMap(\.toolResult)
        let successfulToolCalls = resultEvents.filter(\.ok).count
        let failedToolCalls = resultEvents.count - successfulToolCalls
        let toolCallCount = max(events.compactMap(\.toolCall).count, resultEvents.count)
        let toolTime = resultEvents.reduce(TimeInterval(0)) { total, event in
            total + (Double(event.durationMs ?? 0) / 1_000)
        }
        let activeTime = cumulativeAgentActiveTime + currentAgentActiveTime(now: now)
        return SloppyTUIExitSummary(
            sessionID: hasPersistedSession ? session.id : "not created",
            canResume: hasPersistedSession,
            toolCallCount: toolCallCount,
            successfulToolCallCount: successfulToolCalls,
            failedToolCallCount: failedToolCalls,
            wallTime: now.timeIntervalSince(tuiStartedAt),
            agentActiveTime: activeTime,
            apiTime: max(0, activeTime - toolTime),
            toolTime: toolTime
        )
    }

    func currentAgentActiveTime(now: Date) -> TimeInterval {
        guard let taskStartedAt else {
            return 0
        }
        return max(0, now.timeIntervalSince(taskStartedAt))
    }

    func composerContextTiming() -> (runElapsed: TimeInterval?, stageElapsed: TimeInterval?) {
        let now = Date()
        if let taskStartedAt {
            let stageElapsed = sendTimingLast.map { max(0, now.timeIntervalSince($0)) }
            return (max(0, now.timeIntervalSince(taskStartedAt)), stageElapsed)
        }
        return (lastTaskElapsed, nil)
    }

    func printExitSummary(_ summary: SloppyTUIExitSummary) {
        guard let terminal else {
            return
        }
        let width = max(24, terminal.columns)
        let lines = SloppyTUITheme.exitSummaryLines(summary, width: width)
        tui?.stop()
        terminal.write("\r\n" + lines.joined(separator: "\r\n") + "\r\n")
    }

    func interruptCurrentRunForExit(reason: String) async {
        guard hasPersistedSession else {
            return
        }
        guard isPosting || liveRunStatusLine != nil else {
            return
        }

        isInterruptingRun = true
        refreshStaticChrome(statusLine: "Interrupting active agent run before exit.")
        do {
            _ = try await service.controlAgentSession(
                agentID: agent.id,
                sessionID: session.id,
                request: AgentSessionControlRequest(action: .interruptTree, requestedBy: "tui", reason: reason)
            )
        } catch {
            // Exit should not be blocked by a failed cooperative interrupt request.
        }
    }

    func persistSelection() {
        let key = SloppyTUIStateStore.selectionKey(projectId: project.id)
        state.selections[key] = .init(agentId: agent.id, sessionId: hasPersistedSession ? session.id : nil)
        stateStore.save(state)
    }

    func trackedSessionsKey() -> String {
        SloppyTUIStateStore.trackedSessionsKey(projectId: project.id)
    }

    func trackedSessionsForCurrentProject() -> [SloppyTUIState.TrackedSession] {
        state.trackedSessions[trackedSessionsKey()] ?? []
    }

    func trackSession(
        _ summary: AgentSessionSummary,
        pinned: Bool? = nil,
        background: Bool? = nil,
        worktreePath: String? = nil,
        worktreeBranch: String? = nil,
        opened: Bool = false
    ) {
        let key = trackedSessionsKey()
        var items = state.trackedSessions[key] ?? []
        let now = Date()
        if let index = items.firstIndex(where: { $0.sessionId == summary.id }) {
            var item = items[index]
            item.agentId = summary.agentId
            item.pinned = pinned ?? item.pinned
            item.background = background ?? item.background
            item.worktreePath = worktreePath ?? item.worktreePath
            item.worktreeBranch = worktreeBranch ?? item.worktreeBranch
            if opened {
                item.lastOpenedAt = now
            }
            items[index] = item
        } else {
            items.append(SloppyTUIState.TrackedSession(
                agentId: summary.agentId,
                sessionId: summary.id,
                pinned: pinned ?? false,
                background: background ?? false,
                worktreePath: worktreePath,
                worktreeBranch: worktreeBranch,
                createdAt: now,
                lastOpenedAt: opened ? now : nil
            ))
        }
        state.trackedSessions[key] = items
        stateStore.save(state)
        refreshSessionList()
    }

    func removeTrackedSession(_ sessionID: String) {
        let key = trackedSessionsKey()
        var items = state.trackedSessions[key] ?? []
        items.removeAll { $0.sessionId == sessionID }
        state.trackedSessions[key] = items
        stateStore.save(state)
    }

    func togglePinForCurrentSession() {
        guard hasPersistedSession else {
            appendLocalCard("No session yet. Send a message first or open an existing session with `/sessions`.")
            return
        }
        let key = trackedSessionsKey()
        var items = state.trackedSessions[key] ?? []
        let nextPinned: Bool
        if let index = items.firstIndex(where: { $0.sessionId == session.id }) {
            items[index].pinned.toggle()
            nextPinned = items[index].pinned
        } else {
            let item = SloppyTUIState.TrackedSession(
                agentId: agent.id,
                sessionId: session.id,
                pinned: true,
                createdAt: Date(),
                lastOpenedAt: Date()
            )
            items.append(item)
            nextPinned = true
        }
        state.trackedSessions[key] = items
        stateStore.save(state)
        refreshSessionList()
        appendLocalCard(nextPinned ? "Session pinned." : "Session unpinned.", autoDismissAfter: 6)
    }

    func currentSessionDirectoryKey() -> String {
        SloppyTUIStateStore.sessionDirectoryKey(
            projectId: project.id,
            agentId: agent.id,
            sessionId: session.id
        )
    }

    func persistedDirectoriesForCurrentSession() -> [String] {
        state.sessionDirectories[currentSessionDirectoryKey()] ?? []
    }

    func persistSessionDirectories(_ directories: [String]) {
        let normalized = normalizedDirectoryList(directories)
        let key = currentSessionDirectoryKey()
        if normalized.isEmpty {
            state.sessionDirectories.removeValue(forKey: key)
        } else {
            state.sessionDirectories[key] = normalized
        }
        restoredDirectorySessionKeys.insert(key)
        stateStore.save(state)
    }

    func restorePersistedDirectoriesForCurrentSession() async {
        guard hasPersistedSession else {
            return
        }
        let key = currentSessionDirectoryKey()
        guard restoredDirectorySessionKeys.insert(key).inserted else {
            return
        }

        var restored: [String] = []
        for directory in persistedDirectoriesForCurrentSession() {
            do {
                let response = try await service.addAgentSessionDirectory(
                    agentID: agent.id,
                    sessionID: session.id,
                    request: AgentSessionDirectoryRequest(path: directory)
                )
                restored = response.directories
            } catch {
                continue
            }
        }
        if !restored.isEmpty {
            state.sessionDirectories[key] = normalizedDirectoryList(restored)
            stateStore.save(state)
        }
    }

    func applyDraftDirectories(_ directories: [String], previousKey: String) async {
        var restored: [String] = []
        for directory in directories {
            do {
                let response = try await service.addAgentSessionDirectory(
                    agentID: agent.id,
                    sessionID: session.id,
                    request: AgentSessionDirectoryRequest(path: directory)
                )
                restored = response.directories
            } catch {
                continue
            }
        }

        state.sessionDirectories.removeValue(forKey: previousKey)
        if !restored.isEmpty {
            state.sessionDirectories[currentSessionDirectoryKey()] = normalizedDirectoryList(restored)
            restoredDirectorySessionKeys.insert(currentSessionDirectoryKey())
        }
        stateStore.save(state)
    }

    func normalizedDirectoryList(_ directories: [String]) -> [String] {
        var seen = Set<String>()
        return directories.compactMap { directory in
            let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }
            let normalized = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath, isDirectory: true)
                .resolvingSymlinksInPath()
                .standardizedFileURL
                .path
            guard seen.insert(normalized).inserted else {
                return nil
            }
            return normalized
        }
    }

    func appendingUniqueDirectory(_ directory: String, to directories: [String]) -> [String] {
        normalizedDirectoryList(directories + [directory])
    }

    func resolveDraftSessionDirectoryPath(_ rawPath: String) async throws -> String {
        var trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
            (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            trimmed = String(trimmed.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !trimmed.isEmpty else {
            throw CocoaError(.fileNoSuchFile)
        }

        let expanded = (trimmed as NSString).expandingTildeInPath
        let candidate: URL
        if expanded.hasPrefix("/") {
            candidate = URL(fileURLWithPath: expanded, isDirectory: true)
        } else {
            let root = (try? await service.resolveProjectWorkspaceRoot(projectID: project.id))
                ?? URL(fileURLWithPath: runtime.cwd, isDirectory: true)
            candidate = root.appendingPathComponent(expanded, isDirectory: true)
        }

        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw CocoaError(.fileNoSuchFile)
        }
        return resolved.path
    }

    func persistDraft(_ value: String) {
        let key = SloppyTUIStateStore.draftKey(projectId: project.id, agentId: agent.id, sessionId: session.id)
        if value.isEmpty {
            state.drafts.removeValue(forKey: key)
        } else {
            state.drafts[key] = value
        }
        stateStore.save(state)
    }

    func attachmentURLs(fromPastedText text: String) -> [URL] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let candidates = splitPastedPathCandidates(trimmed)
        guard !candidates.isEmpty else { return [] }

        var urls: [URL] = []
        for candidate in candidates {
            if let url = fileURL(fromPastedPathCandidate: candidate),
               FileManager.default.fileExists(atPath: url.path) {
                urls.append(url)
            } else {
                return []
            }
        }
        return urls
    }

    func splitPastedPathCandidates(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.count > 1 {
            return lines.map(Self.unquotePathCandidate)
        }

        let single = Self.unquotePathCandidate(normalized.trimmingCharacters(in: .whitespacesAndNewlines))
        if FileManager.default.fileExists(atPath: (single as NSString).expandingTildeInPath)
            || single.hasPrefix("file://") {
            return [single]
        }

        return splitEscapedShellPaths(single)
    }

    func splitEscapedShellPaths(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var isEscaped = false
        var quote: Character?

        for character in text {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }
            if character == "\\" {
                isEscaped = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll()
                }
            } else {
                current.append(character)
            }
        }
        if isEscaped {
            current.append("\\")
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    func fileURL(fromPastedPathCandidate candidate: String) -> URL? {
        if candidate.hasPrefix("file://") {
            return URL(string: candidate.removingPercentEncoding ?? candidate)
        }
        let raw = candidate.removingPercentEncoding ?? candidate
        let expanded = (raw as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return URL(fileURLWithPath: runtime.cwd)
            .appendingPathComponent(expanded)
            .standardizedFileURL
    }

    static func unquotePathCandidate(_ value: String) -> String {
        var result = value
        if result.count >= 2,
           let first = result.first,
           let last = result.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            result.removeFirst()
            result.removeLast()
        }
        return result.replacingOccurrences(of: "\\ ", with: " ")
    }

    func addPendingAttachmentFiles(_ urls: [URL]) {
        var added: [String] = []
        var skipped: [String] = []
        var imageMarkers: [String] = []
        for url in urls {
            if SloppyTUIAttachmentContext.isImagePath(url.path) {
                imageMarkers.append(SloppyTUIAttachmentContext.imageMarker(filename: url.lastPathComponent))
                continue
            }
            do {
                let upload = try makeAttachmentUpload(from: url)
                pendingUploads.append(upload)
                added.append(upload.name)
            } catch {
                skipped.append("\(url.lastPathComponent): \(String(describing: error))")
            }
        }
        if !imageMarkers.isEmpty {
            insertImageMarkersIntoEditor(imageMarkers)
            showSystemNotice("Inserted image reference" + (imageMarkers.count == 1 ? "." : "s."))
        }
        if !added.isEmpty {
            showSystemNotice("Attached \(added.count) file(s): \(added.joined(separator: ", "))")
        }
        if !skipped.isEmpty {
            showSystemNotice("Attachment skipped: " + skipped.joined(separator: "; "))
        }
        refreshStaticChrome()
    }

    func insertImageMarkersIntoEditor(_ markers: [String]) {
        let text = markers.joined(separator: "\n")
        guard !text.isEmpty else { return }
        editor.handle(input: .paste(text))
    }

    func imageMarkers(fromPastedText text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let candidates = splitPastedPathCandidates(trimmed)
        guard !candidates.isEmpty,
              candidates.allSatisfy({ SloppyTUIAttachmentContext.isImagePath($0) })
        else { return [] }
        return candidates.map { SloppyTUIAttachmentContext.imageMarker(forPath: $0) }
    }

    func makeAttachmentUpload(from url: URL) throws -> AgentAttachmentUpload {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw SloppyTUIAttachmentError.notAFile
        }

        let data = try Data(contentsOf: url)
        guard data.count <= SloppyTUIAttachmentLimits.maxBytes else {
            throw SloppyTUIAttachmentError.tooLarge(data.count)
        }
        return AgentAttachmentUpload(
            name: url.lastPathComponent.isEmpty ? "attachment.bin" : url.lastPathComponent,
            mimeType: mimeType(for: url),
            sizeBytes: data.count,
            contentBase64: data.base64EncodedString()
        )
    }

    func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "tif", "tiff": return "image/tiff"
        case "pdf": return "application/pdf"
        case "json": return "application/json"
        case "md", "markdown": return "text/markdown"
        case "txt", "log": return "text/plain"
        case "csv": return "text/csv"
        case "html", "htm": return "text/html"
        case "swift": return "text/x-swift"
        default: return "application/octet-stream"
        }
    }

    func pasteAttachmentFromClipboard() {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty {
            addPendingAttachmentFiles(urls)
            return
        }

        if let text = pasteboard.string(forType: .string) {
            let imageMarkers = imageMarkers(fromPastedText: text)
            if !imageMarkers.isEmpty {
                insertImageMarkersIntoEditor(imageMarkers)
                showSystemNotice("Inserted image reference" + (imageMarkers.count == 1 ? "." : "s."))
                refreshStaticChrome()
                return
            }
            let urls = attachmentURLs(fromPastedText: text)
            if !urls.isEmpty {
                addPendingAttachmentFiles(urls)
                return
            }
        }

        if let pngData = pasteboard.data(forType: NSPasteboard.PasteboardType("public.png")) {
            addPendingClipboardImage(data: pngData, mimeType: "image/png", extension: "png")
            return
        }
        if let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData),
           let pngData = image.pngData() {
            addPendingClipboardImage(data: pngData, mimeType: "image/png", extension: "png")
            return
        }
        showSystemNotice("Clipboard does not contain a file, image, or file path.")
        #else
        showSystemNotice("Clipboard image paste is only available on macOS.")
        #endif
    }

    func addPendingClipboardImage(data: Data, mimeType: String, extension pathExtension: String) {
        guard data.count <= SloppyTUIAttachmentLimits.maxBytes else {
            showSystemNotice("Clipboard image is too large (\(data.count) bytes).")
            return
        }
        let name = "clipboard-\(Self.clipboardTimestamp()).\(pathExtension)"
        insertImageMarkersIntoEditor([SloppyTUIAttachmentContext.imageMarker(filename: name)])
        showSystemNotice("Inserted clipboard image reference: \(name)")
        refreshStaticChrome()
    }

    static func clipboardTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    func messageContentWithInlineAttachments(
        _ raw: String,
        context: String?,
        uploads: [AgentAttachmentUpload]
    ) async -> String {
        var parts = [raw]
        if let pendingContext = context {
            parts.append("\n[Attached context]\n\(pendingContext)")
        }
        if !uploads.isEmpty {
            let list = uploads.map { "- \($0.name) (\($0.mimeType), \($0.sizeBytes) bytes)" }.joined(separator: "\n")
            parts.append("\n[Attached files]\n\(list)")
        }

        let paths = SloppyTUIProjectPathTokens.attachmentPaths(in: raw)
        for path in paths.prefix(8) {
            parts.append("\n\(await projectPathContext(for: path))")
        }
        return parts.joined(separator: "\n")
    }

    func projectPathContext(for rawPath: String) async -> String {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("/") {
            if service.isRemote {
                return "[Attachment failed: \(path)] Absolute local paths are disabled for remote Sloppy instances."
            }
            return absolutePathContext(for: path)
        }
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cachedType = projectFileIndex?.entries.first { $0.path == normalizedPath }?.type
        let shouldTryDirectoryFirst = path.hasSuffix("/") || cachedType == .directory

        if shouldTryDirectoryFirst, let manifest = await directoryContextBlock(path: path) {
            return manifest
        }

        do {
            return try await projectFileReferenceContext(for: path)
        } catch {
            if !shouldTryDirectoryFirst, let manifest = await directoryContextBlock(path: path) {
                return manifest
            }
            scheduleProjectFileReindex()
            if SloppyTUIAttachmentContext.isImagePath(path) {
                return SloppyTUIAttachmentContext.imageMarker(forPath: path)
            }
            return "[Attachment failed: \(path)] Cached path is stale or unavailable: \(String(describing: error))"
        }
    }

    func directoryContextBlock(path: String) async -> String? {
        if path.hasPrefix("/") {
            return absoluteDirectoryContextBlock(path: path)
        }
        let manifestLimit = 80
        do {
            if service.isRemote {
                let entries = try await service.searchProjectFiles(projectID: project.id, query: path, limit: manifestLimit)
                let normalized = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let prefix = normalized.isEmpty ? "" : normalized + "/"
                let lines = entries
                    .filter { normalized.isEmpty || $0.path == normalized || $0.path.hasPrefix(prefix) }
                    .map { entry in "- \(entry.path)\(entry.type == .directory ? "/" : "")" }
                    .joined(separator: "\n")
                return """
                [Attached directory: \(normalized)/]
                \(lines.isEmpty ? "- (empty directory)" : lines)
                """
            }
            let rootURL: URL
            if let projectFileRootURL {
                rootURL = projectFileRootURL
            } else {
                rootURL = try await service.resolveProjectWorkspaceRoot(projectID: project.id)
                projectFileRootURL = rootURL
            }

            let projectID = project.id
            let entries = try await Task.detached(priority: .utility) {
                try ProjectFileIndex.directoryManifest(
                    projectId: projectID,
                    rootURL: rootURL,
                    path: path,
                    limit: manifestLimit
                )
            }.value
            let normalized = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let lines = entries.map { entry in
                let suffix = entry.type == .directory ? "/" : ""
                return "- \(entry.path)\(suffix)"
            }.joined(separator: "\n")
            let body = lines.isEmpty ? "- (empty directory)" : lines
            return """
            [Attached directory: \(normalized)/]
            \(body)
            """
        } catch {
            return nil
        }
    }

    func absolutePathContext(for rawPath: String) -> String {
        guard let url = allowedAbsoluteAttachmentURL(rawPath) else {
            return "[Attachment failed: \(rawPath)] Path is outside directories added with `/add_dir`."
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return "[Attachment failed: \(rawPath)] Path does not exist."
        }
        if isDirectory.boolValue {
            return absoluteDirectoryContextBlock(path: url.path) ?? "[Attached directory: \(url.path)/]\n- (empty directory)"
        }

        return fileReferenceContextBlock(displayPath: url.path, url: url)
    }

    func absoluteDirectoryContextBlock(path: String) -> String? {
        guard let url = allowedAbsoluteAttachmentURL(path) else {
            return nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return nil
        }

        let entries = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let lines = entries
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(80)
            .map { entry -> String in
                let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
                return "- \(entry.path)\((values?.isDirectory == true) ? "/" : "")"
            }
            .joined(separator: "\n")
        return """
        [Attached directory: \(url.path)/]
        \(lines.isEmpty ? "- (empty directory)" : lines)
        """
    }

    func allowedAbsoluteAttachmentURL(_ rawPath: String) -> URL? {
        let candidate = URL(fileURLWithPath: rawPath, isDirectory: false)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        for directory in persistedDirectoriesForCurrentSession() {
            let root = URL(fileURLWithPath: directory, isDirectory: true)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
            if candidate.path == root.path || candidate.path.hasPrefix(rootPrefix) {
                return candidate
            }
        }
        return nil
    }

    func projectFileReferenceContext(for rawPath: String) async throws -> String {
        if service.isRemote {
            let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPath.isEmpty else {
                throw SloppyTUIAttachmentReferenceError.invalidPath
            }
            let response = try await service.readProjectFile(projectID: project.id, path: trimmedPath)
            return SloppyTUIAttachmentContext.fileReferenceBlock(
                displayPath: response.path,
                absolutePath: response.path,
                sizeBytes: response.sizeBytes
            )
        }
        let rootURL: URL
        if let projectFileRootURL {
            rootURL = projectFileRootURL
        } else {
            rootURL = try await service.resolveProjectWorkspaceRoot(projectID: project.id)
            projectFileRootURL = rootURL
        }

        let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw SloppyTUIAttachmentReferenceError.invalidPath
        }

        let fileURL = rootURL.appendingPathComponent(trimmedPath).standardizedFileURL
        guard isAttachmentURL(fileURL, inside: rootURL) else {
            throw SloppyTUIAttachmentReferenceError.invalidPath
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
            throw SloppyTUIAttachmentReferenceError.notFound
        }
        guard !isDirectory.boolValue else {
            throw SloppyTUIAttachmentReferenceError.notFile
        }

        let relativePath = String(fileURL.path.dropFirst(rootURL.standardizedFileURL.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return fileReferenceContextBlock(displayPath: relativePath.isEmpty ? trimmedPath : relativePath, url: fileURL)
    }

    func fileReferenceContextBlock(displayPath: String, url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return SloppyTUIAttachmentContext.fileReferenceBlock(
            displayPath: displayPath,
            absolutePath: url.path,
            sizeBytes: values?.fileSize
        )
    }

    func isAttachmentURL(_ url: URL, inside rootURL: URL) -> Bool {
        let root = rootURL.standardizedFileURL
        let candidate = url.standardizedFileURL
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return candidate.path == root.path || candidate.path.hasPrefix(rootPrefix)
    }
}

enum SloppyTUIAttachmentReferenceError: Error {
    case invalidPath
    case notFound
    case notFile
}
