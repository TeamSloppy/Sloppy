import Foundation
import Protocols

struct GitHubPullRequestEvents: Decodable {
    struct User: Decodable { let login: String }
    struct Repository: Decodable { let full_name: String }
    struct Head: Decodable { let sha: String }
    struct PullRequest: Decodable {
        let number: Int
        let title: String
        let html_url: String
        let state: String
        let user: User
        let draft: Bool?
        let head: Head?
        let pull_request: [String: JSONValue]?
    }
    struct Feedback: Decodable {
        let id: Int
        let body: String?
        let user: User
        let path: String?
        let line: Int?
        let in_reply_to_id: Int?
    }

    let action: String
    let repository: Repository
    let sender: User
    let pull_request: PullRequest?
    let issue: PullRequest?
    let requested_reviewer: User?
    let comment: Feedback?
    let review: Feedback?

    func event(type: String, deliveryID: String, settings: PullRequestAutomationSettings) -> PullRequestEvent? {
        guard let pr = pull_request ?? issue, pr.state == "open", pr.draft != true,
              settings.reviewIDs.isEmpty || settings.reviewIDs.contains(String(pr.number)) else { return nil }
        let account = settings.account.lowercased()
        let authored = pr.user.login.lowercased() == account
        let repo = repository.full_name
        let reference = CodeReviewReference(providerId: "github", reviewId: "github:\(repo)#\(pr.number)", repository: repo)
        if type == "pull_request", !authored, settings.kinds.contains(.reviewRequested) {
            let requested = action == "review_requested" && requested_reviewer?.login.lowercased() == account
            let opened = settings.reviewNewGitHubPullRequests == true && ["opened", "ready_for_review"].contains(action)
            guard requested || opened else { return nil }
            let key = settings.reviewNewGitHubPullRequests == true ? pr.head?.sha ?? deliveryID : deliveryID
            return .init(id: "review:\(pr.number):\(key)", kind: .reviewRequested, review: reference,
                         title: pr.title, url: pr.html_url, actor: sender.login, revision: pr.head?.sha)
        }

        guard authored, settings.kinds.contains(.feedbackReceived) else { return nil }
        let feedback: Feedback?
        let prefix: String
        switch (type, action) {
        case ("pull_request_review_comment", "created"):
            feedback = comment
            prefix = "github-review-comment"
        case ("issue_comment", "created") where issue?.pull_request != nil:
            feedback = comment
            prefix = "github-issue-comment"
        case ("pull_request_review", "submitted"):
            feedback = review
            prefix = "github-review"
        default:
            return nil
        }
        guard let feedback, feedback.user.login.lowercased() != account,
              let body = feedback.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let commentID = "\(prefix)-\(feedback.id)"
        return .init(
            id: "feedback:\(pr.number):\(commentID)", kind: .feedbackReceived, review: reference,
            title: pr.title, url: pr.html_url, actor: feedback.user.login, revision: pr.head?.sha,
            comment: .init(id: commentID, author: feedback.user.login, body: String(body.prefix(12_000)),
                           filePath: feedback.path, line: feedback.line, inReplyToId: feedback.in_reply_to_id.map(String.init))
        )
    }
}

extension CoreService {
    func receiveGitHubPullRequestEvent(body: Data, signature: String?, type: String?, deliveryID: String?) throws -> Int {
        guard let secret = ProcessInfo.processInfo.environment["SLOPPY_GITHUB_PR_WEBHOOK_SECRET"],
              !secret.isEmpty, TaskSyncCrypto.verifyGitHubSignature(body: body, secret: secret, signatureHeader: signature)
        else { throw TaskSyncError.signatureInvalid }
        guard let type, let deliveryID, !deliveryID.isEmpty,
              ["pull_request", "pull_request_review", "pull_request_review_comment", "issue_comment"].contains(type)
        else { return 0 }
        let payload = try JSONDecoder().decode(GitHubPullRequestEvents.self, from: body)
        let fingerprint = TaskSyncCrypto.sha256Hex(body)
        let storage = pullRequestAutomationStore
        var accepted = 0
        for var subscription in try storage.list() where subscription.settings.enabled
            && subscription.settings.githubRepository?.lowercased() == payload.repository.full_name.lowercased() {
            guard let event = payload.event(type: type, deliveryID: fingerprint, settings: subscription.settings) else { continue }
            let count = subscription.pending.count
            subscription.receive([event])
            if count != subscription.pending.count {
                try storage.save(subscription)
                accepted += 1
            }
        }
        return accepted
    }
}
