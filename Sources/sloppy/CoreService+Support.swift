import Foundation
import Protocols

// MARK: - Support

extension CoreService {
    public func createIssueReport(request: IssueReportRequest = IssueReportRequest()) throws -> IssueReportResponse {
        let requestedLimit = request.logLimit ?? 200
        let logLimit = min(max(requestedLimit, 1), 1_000)
        do {
            let logs = try systemLogStore.readRecentEntries(limit: logLimit)
            let redactor = SensitiveLogRedactor(config: currentConfig)
            let builder = IssueReportBuilder(redactor: redactor)
            return builder.makeResponse(logs: logs, build: BuildMetadataResolver().resolve())
        } catch {
            throw SystemLogsError.storageFailure
        }
    }
}
