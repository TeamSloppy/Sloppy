import Foundation
import Observation
import SloppyClientCore

public enum TaskActivityTab: String, CaseIterable, Identifiable, Sendable {
    case comments, technical, history, logs, related, review, clarifications
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .comments: "Comments"
        case .technical: "Technical"
        case .history: "History"
        case .logs: "Logs"
        case .related: "Related tasks"
        case .review: "Review"
        case .clarifications: "Clarifications"
        }
    }
}

@MainActor @Observable
public final class TaskActivityViewModel {
    public private(set) var comments: [TaskComment] = []
    public private(set) var activities: [APITaskActivity] = []
    public private(set) var logs: [APITaskLog] = []
    public private(set) var clarifications: [APITaskClarification] = []
    public private(set) var diffLines: [String] = []
    public private(set) var diff: APITaskDiff?
    public private(set) var reviewComments: [APITaskReviewComment] = []
    public private(set) var reviewNotice: String?
    public private(set) var isLoading = false
    public private(set) var isSubmitting = false
    public private(set) var errorMessage: String?
    public private(set) var actionError: String?
    public private(set) var revision = 0
    @ObservationIgnored private let api: SloppyAPIClient
    @ObservationIgnored private var scope = ""
    @ObservationIgnored private var loaded: Set<TaskActivityTab> = []
    @ObservationIgnored private var requestID = UUID()

    public init(api: SloppyAPIClient) { self.api = api }

    public func hasLoaded(_ tab: TaskActivityTab) -> Bool { loaded.contains(tab == .technical ? .comments : tab) }

    public func load(_ tab: TaskActivityTab, projectId: String, taskId: String, force: Bool = false) async {
        let nextScope = "\(projectId):\(taskId)"
        if scope != nextScope {
            scope = nextScope
            loaded = []
            comments = []; activities = []; logs = []; clarifications = []
            diff = nil; diffLines = []; reviewComments = []; reviewNotice = nil; actionError = nil
            revision &+= 1
        }
        let id = UUID()
        requestID = id
        errorMessage = nil
        let key: TaskActivityTab = tab == .technical ? .comments : tab
        guard force || !loaded.contains(key) else { isLoading = false; return }
        isLoading = true
        defer { if requestID == id { isLoading = false } }
        do {
            switch key {
            case .comments, .technical:
                let records = try await api.fetchTaskComments(projectId: projectId, taskId: taskId)
                let sorted = try await ClientBackgroundWork.run { records.sorted { $0.createdAt > $1.createdAt } }
                guard requestID == id, !Task.isCancelled else { return }
                comments = sorted
                revision &+= 1
            case .history:
                let records = try await api.fetchTaskActivities(projectId: projectId, taskId: taskId)
                let sorted = try await ClientBackgroundWork.run { records.sorted { $0.createdAt > $1.createdAt } }
                guard requestID == id, !Task.isCancelled else { return }
                activities = sorted
            case .logs:
                let records = try await api.fetchTaskLogs(projectId: projectId, taskId: taskId)
                guard requestID == id, !Task.isCancelled else { return }
                logs = records
            case .clarifications:
                let records = try await api.fetchTaskClarifications(projectId: projectId, taskId: taskId)
                guard requestID == id, !Task.isCancelled else { return }
                clarifications = records
            case .review:
                async let commentRequest = api.fetchTaskReviewComments(projectId: projectId, taskId: taskId)
                var result: APITaskDiff?
                var notice: String?
                do { result = try await api.fetchTaskDiff(projectId: projectId, taskId: taskId) }
                catch { notice = "Diff unavailable: \(error.localizedDescription)" }
                let records = try await commentRequest
                let diffText = result?.diff ?? ""
                let lines = try await ClientBackgroundWork.run { diffText.components(separatedBy: "\n") }
                guard requestID == id, !Task.isCancelled else { return }
                diffLines = lines
                diff = result; reviewNotice = notice; reviewComments = records
            case .related: break
            }
            guard requestID == id, !Task.isCancelled else { return }
            loaded.insert(key)
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    public func addComment(_ content: String, projectId: String, taskId: String) async -> Bool {
        guard !isSubmitting, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        isSubmitting = true; actionError = nil
        defer { isSubmitting = false }
        do {
            let comment = try await api.addTaskComment(projectId: projectId, taskId: taskId, content: content)
            guard scope == "\(projectId):\(taskId)" else { return true }
            comments.insert(comment, at: 0); revision &+= 1
            return true
        } catch { actionError = error.localizedDescription; return false }
    }

    public func answer(_ clarification: APITaskClarification, selected: [String], note: String,
                       projectId: String, taskId: String) async {
        guard !isSubmitting else { return }
        isSubmitting = true; actionError = nil
        defer { isSubmitting = false }
        do {
            let answer = try await api.answerTaskClarification(projectId: projectId, taskId: taskId,
                clarificationId: clarification.id, answer: APITaskClarificationAnswer(selectedOptionIds: selected, note: note))
            if scope == "\(projectId):\(taskId)", let index = clarifications.firstIndex(where: { $0.id == answer.id }) {
                clarifications[index] = answer
            }
        } catch { actionError = error.localizedDescription }
    }

    public func decideReview(approve: Bool, reason: String, projectId: String, taskId: String) async -> Bool {
        guard !isSubmitting else { return false }
        isSubmitting = true; actionError = nil
        defer { isSubmitting = false }
        do {
            try await api.decideTaskReview(projectId: projectId, taskId: taskId, approve: approve, reason: reason)
            loaded.remove(.history); loaded.remove(.logs); loaded.remove(.comments)
            return true
        } catch { actionError = error.localizedDescription; return false }
    }

    public func resolveReviewComment(_ comment: APITaskReviewComment, projectId: String, taskId: String) async {
        guard !isSubmitting else { return }
        isSubmitting = true; actionError = nil
        defer { isSubmitting = false }
        do {
            let updated = try await api.resolveTaskReviewComment(projectId: projectId, taskId: taskId, commentId: comment.id, resolved: !comment.resolved)
            if scope == "\(projectId):\(taskId)", let index = reviewComments.firstIndex(where: { $0.id == updated.id }) { reviewComments[index] = updated }
        } catch { actionError = error.localizedDescription }
    }

    nonisolated public static func filterComments(_ comments: [TaskComment], technical: Bool,
                                                  query: String, newestFirst: Bool) -> [TaskComment] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = comments.filter {
            $0.isTechnical == technical && (query.isEmpty || $0.content.localizedCaseInsensitiveContains(query)
                || ($0.sourceAuthor ?? $0.authorActorId).localizedCaseInsensitiveContains(query))
        }
        return filtered.sorted {
            if $0.createdAt == $1.createdAt { return $0.id < $1.id }
            return newestFirst ? $0.createdAt > $1.createdAt : $0.createdAt < $1.createdAt
        }
    }
}
