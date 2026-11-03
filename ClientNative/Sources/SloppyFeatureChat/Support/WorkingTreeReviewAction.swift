import SwiftUI
import SloppyClientCore

public typealias WorkingTreeReviewHandler = @MainActor @Sendable (
    ProjectWorkingTreeSourceControlResponse, String?, String?
) -> Void

public extension EnvironmentValues {
    @Entry var workingTreeReviewHandler: WorkingTreeReviewHandler? = nil
}
