import Foundation
import Protocols

/// Wraps a task sync provider implementation for return through `sloppy_task_sync_create`.
///
/// Source plugins that declare `"protocol": "task_sync"` in `plugin.json` should export
/// a C ABI entrypoint with this contract:
///
/// ```swift
/// @_cdecl("sloppy_task_sync_create")
/// public func sloppy_task_sync_create(
///     _ manifestJSON: UnsafePointer<CChar>
/// ) -> UnsafeMutableRawPointer?
/// ```
///
/// The returned pointer must be an `Unmanaged.passRetained(AnyTaskSyncProviderBox(...)).toOpaque()`.
public final class AnyTaskSyncProviderBox: TaskSyncProvider, @unchecked Sendable {
    public let id: String

    private let _parseProjectURL: @Sendable (String) throws -> TaskSyncProjectDescriptor
    private let _resolveProject: @Sendable (String, String?, String?) async throws -> TaskSyncProjectDescriptor
    private let _importTasks: @Sendable (ProjectTaskSyncSettings, String?) async throws -> [TaskSyncExternalTask]
    private let _createOrUpdateTask: @Sendable (ProjectTask, ProjectTaskSyncSettings, String?) async throws -> TaskExternalMetadata
    private let _mirrorComment: @Sendable (TaskComment, ProjectTask, ProjectTaskSyncSettings, String?) async throws -> TaskExternalMetadata

    public init(
        id: String,
        parseProjectURL: @escaping @Sendable (String) throws -> TaskSyncProjectDescriptor,
        resolveProject: @escaping @Sendable (String, String?, String?) async throws -> TaskSyncProjectDescriptor,
        importTasks: @escaping @Sendable (ProjectTaskSyncSettings, String?) async throws -> [TaskSyncExternalTask],
        createOrUpdateTask: @escaping @Sendable (ProjectTask, ProjectTaskSyncSettings, String?) async throws -> TaskExternalMetadata,
        mirrorComment: @escaping @Sendable (TaskComment, ProjectTask, ProjectTaskSyncSettings, String?) async throws -> TaskExternalMetadata
    ) {
        self.id = id
        self._parseProjectURL = parseProjectURL
        self._resolveProject = resolveProject
        self._importTasks = importTasks
        self._createOrUpdateTask = createOrUpdateTask
        self._mirrorComment = mirrorComment
    }

    public func parseProjectURL(_ rawURL: String) throws -> TaskSyncProjectDescriptor {
        try _parseProjectURL(rawURL)
    }

    public func resolveProject(
        url: String,
        token: String?,
        defaultRepo: String?
    ) async throws -> TaskSyncProjectDescriptor {
        try await _resolveProject(url, token, defaultRepo)
    }

    public func importTasks(
        settings: ProjectTaskSyncSettings,
        token: String?
    ) async throws -> [TaskSyncExternalTask] {
        try await _importTasks(settings, token)
    }

    public func createOrUpdateTask(
        _ task: ProjectTask,
        settings: ProjectTaskSyncSettings,
        token: String?
    ) async throws -> TaskExternalMetadata {
        try await _createOrUpdateTask(task, settings, token)
    }

    public func mirrorComment(
        _ comment: TaskComment,
        task: ProjectTask,
        settings: ProjectTaskSyncSettings,
        token: String?
    ) async throws -> TaskExternalMetadata {
        try await _mirrorComment(comment, task, settings, token)
    }
}
