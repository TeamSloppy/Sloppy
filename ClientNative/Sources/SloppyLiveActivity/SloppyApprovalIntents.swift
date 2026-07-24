#if os(iOS)
@preconcurrency import ActivityKit
import AppIntents
import Foundation
import SloppyClientCore

public struct ApproveSloppyToolIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Allow Sloppy Tool"
    public static let description = IntentDescription("Allow the tool request shown by Sloppy.")

    @Parameter(title: "Approval ID")
    public var approvalID: String

    @Parameter(title: "Server URL")
    public var serverURL: String

    public init() {
        approvalID = ""
        serverURL = ""
    }

    public init(approvalID: String, serverURL: String) {
        self.approvalID = approvalID
        self.serverURL = serverURL
    }

    public func perform() async throws -> some IntentResult {
        await SloppyApprovalIntentPerformer.perform(
            approvalID: approvalID,
            serverURL: serverURL,
            approved: true
        )
        return .result()
    }
}

public struct RejectSloppyToolIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Deny Sloppy Tool"
    public static let description = IntentDescription("Deny the tool request shown by Sloppy.")

    @Parameter(title: "Approval ID")
    public var approvalID: String

    @Parameter(title: "Server URL")
    public var serverURL: String

    public init() {
        approvalID = ""
        serverURL = ""
    }

    public init(approvalID: String, serverURL: String) {
        self.approvalID = approvalID
        self.serverURL = serverURL
    }

    public func perform() async throws -> some IntentResult {
        await SloppyApprovalIntentPerformer.perform(
            approvalID: approvalID,
            serverURL: serverURL,
            approved: false
        )
        return .result()
    }
}

private enum SloppyApprovalIntentPerformer {
    static func perform(approvalID: String, serverURL: String, approved: Bool) async {
        guard !approvalID.isEmpty,
              let baseURL = URL(string: serverURL),
              let scheme = baseURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            await updateActivities(
                approvalID: approvalID,
                errorMessage: "The Sloppy server address is invalid."
            )
            return
        }

        do {
            try await SloppyAPIClient(baseURL: baseURL).resolveToolApproval(
                id: approvalID,
                approved: approved
            )
            await updateActivities(approvalID: approvalID, errorMessage: nil)
        } catch {
            let message = error.localizedDescription
            await updateActivities(approvalID: approvalID, errorMessage: message)
        }
    }

    private static func updateActivities(approvalID: String, errorMessage: String?) async {
        for activity in Activity<SloppyActivityAttributes>.activities
        where activity.content.state.approval?.id == approvalID {
            var state = activity.content.state
            if let errorMessage {
                state.error = SloppyActivityError(
                    title: "Approval failed",
                    message: errorMessage
                )
            } else {
                state.approval = nil
                state.error = nil
            }
            state.updatedAt = Date()
            await activity.update(
                ActivityContent(
                    state: state,
                    staleDate: Date().addingTimeInterval(30)
                )
            )
        }
    }

}
#endif
