import Foundation
import Protocols

struct RedactionResult: Sendable, Equatable {
    var value: String
    var count: Int
}

struct SensitiveLogRedactor: Sendable {
    static let marker = "[REDACTED]"

    private static let sensitiveKeyPattern = #"(?i)(token|secret|password|passwd|api[_-]?key|authorization|credential|login|username)"#
    private static let inlinePatterns: [(pattern: String, template: String)] = [
        (#"(?i)(bearer\s+)[A-Za-z0-9._~+/\-]+=*"#, "$1[REDACTED]"),
        (#"(?i)(authorization\s*[:=]\s*)(bearer\s+)?[^\s,}\]]+"#, "$1$2[REDACTED]"),
        (#"(https?://)([^\s/@:]+):([^\s/@]+)@"#, "$1[REDACTED]@"),
        (#"(?i)(["']?(?:token|secret|password|passwd|apiKey|api_key|authorization|credential|login|username)["']?\s*[:=]\s*["']?)([^"',\s}\]]+)"#, "$1[REDACTED]"),
        (#"\bsk-ant-[A-Za-z0-9_\-]{12,}\b"#, "[REDACTED]"),
        (#"\bsk-[A-Za-z0-9_\-]{12,}\b"#, "[REDACTED]"),
        (#"\bghp_[A-Za-z0-9_]{10,}\b"#, "[REDACTED]"),
        (#"\bgithub_pat_[A-Za-z0-9_]+\b"#, "[REDACTED]"),
        (#"\b[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\b"#, "[REDACTED]"),
        (#"\b\d{6,12}:[A-Za-z0-9_\-]{20,}\b"#, "[REDACTED]")
    ]

    private let sensitiveValues: [String]

    init(
        config: CoreConfig,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        var values = Set<String>()
        Self.collectSensitiveValues(from: config, into: &values)
        for (key, value) in environment where Self.isSensitiveKey(key) {
            Self.insertSensitiveValue(value, into: &values)
        }
        sensitiveValues = values.sorted { left, right in
            if left.count == right.count {
                return left < right
            }
            return left.count > right.count
        }
    }

    func redact(_ input: String) -> RedactionResult {
        guard !input.isEmpty else {
            return RedactionResult(value: input, count: 0)
        }

        var output = input
        var count = 0
        for value in sensitiveValues {
            let parts = output.components(separatedBy: value)
            let matches = parts.count - 1
            if matches > 0 {
                output = parts.joined(separator: Self.marker)
                count += matches
            }
        }

        for item in Self.inlinePatterns {
            let result = Self.replaceMatches(in: output, pattern: item.pattern, template: item.template)
            output = result.value
            count += result.count
        }

        return RedactionResult(value: output, count: count)
    }

    func redactMetadata(_ metadata: [String: String]) -> (metadata: [String: String], count: Int) {
        var output: [String: String] = [:]
        var count = 0
        for (key, value) in metadata {
            if Self.isSensitiveKey(key) {
                output[key] = Self.marker
                if !value.isEmpty {
                    count += 1
                }
                continue
            }

            let redacted = redact(value)
            output[key] = redacted.value
            count += redacted.count
        }
        return (output, count)
    }

    static func isSensitiveKey(_ key: String) -> Bool {
        replaceMatches(in: key, pattern: sensitiveKeyPattern, template: "").count > 0
    }

    private static func collectSensitiveValues(from config: CoreConfig, into values: inout Set<String>) {
        guard
            let data = try? JSONEncoder().encode(config),
            let object = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            return
        }
        collectSensitiveValues(from: object, key: nil, into: &values)
    }

    private static func collectSensitiveValues(from object: Any, key: String?, into values: inout Set<String>) {
        if let map = object as? [String: Any] {
            for (childKey, value) in map {
                collectSensitiveValues(from: value, key: childKey, into: &values)
            }
            return
        }

        if let list = object as? [Any] {
            for value in list {
                collectSensitiveValues(from: value, key: key, into: &values)
            }
            return
        }

        guard let key, isSensitiveKey(key) else {
            return
        }

        if let value = object as? String {
            insertSensitiveValue(value, into: &values)
        } else if let value = object as? CustomStringConvertible {
            insertSensitiveValue(value.description, into: &values)
        }
    }

    private static func insertSensitiveValue(_ raw: String, into values: inout Set<String>) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4, trimmed != Self.marker, !Self.marker.contains(trimmed) else {
            return
        }
        values.insert(trimmed)
    }

    private static func replaceMatches(in input: String, pattern: String, template: String) -> RedactionResult {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return RedactionResult(value: input, count: 0)
        }

        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        let matches = regex.matches(in: input, range: range)
        guard !matches.isEmpty else {
            return RedactionResult(value: input, count: 0)
        }
        let output = regex.stringByReplacingMatches(
            in: input,
            range: range,
            withTemplate: template
        )
        return RedactionResult(value: output, count: matches.count)
    }
}

struct IssueReportBuilder: Sendable {
    private static let issueBaseURL = "https://github.com/TeamSloppy/Sloppy/issues/new"
    private static let templateName = "report-an-issue.yml"
    private static let maxIssueURLBytes = 14_000

    let redactor: SensitiveLogRedactor
    let processInfo: ProcessInfo

    init(redactor: SensitiveLogRedactor, processInfo: ProcessInfo = .processInfo) {
        self.redactor = redactor
        self.processInfo = processInfo
    }

    func makeResponse(logs: SystemLogsResponse, build: BuildMetadata) -> IssueReportResponse {
        let sanitized = sanitizeEntries(logs.entries)
        let environment = environmentText(build: build)
        var includedCount = sanitized.entries.count
        var truncated = false

        var logsText = formatLogs(Array(sanitized.entries.suffix(includedCount)))
        var issueURL = makeIssueURL(environment: environment, logs: logsText)

        while issueURL.utf8.count > Self.maxIssueURLBytes && includedCount > 1 {
            truncated = true
            includedCount = max(1, includedCount / 2)
            logsText = formatLogs(Array(sanitized.entries.suffix(includedCount)))
            issueURL = makeIssueURL(environment: environment, logs: logsText)
        }

        if issueURL.utf8.count > Self.maxIssueURLBytes {
            truncated = true
            logsText = truncatedLogsText(logsText, environment: environment)
            issueURL = makeIssueURL(environment: environment, logs: logsText)
        }

        if issueURL.utf8.count > Self.maxIssueURLBytes {
            truncated = true
            includedCount = 0
            logsText = "[logs omitted: report URL length limit reached]"
            issueURL = makeIssueURL(environment: environment, logs: logsText)
        }

        return IssueReportResponse(
            issueUrl: issueURL,
            logEntryCount: includedCount,
            redactionCount: sanitized.redactionCount,
            truncated: truncated
        )
    }

    private func sanitizeEntries(_ entries: [SystemLogEntry]) -> (entries: [SystemLogEntry], redactionCount: Int) {
        var redactionCount = 0
        let sanitized = entries.map { entry in
            let label = redactor.redact(entry.label)
            let message = redactor.redact(entry.message)
            let source = redactor.redact(entry.source)
            let metadata = redactor.redactMetadata(entry.metadata)
            redactionCount += label.count + message.count + source.count + metadata.count
            return SystemLogEntry(
                timestamp: entry.timestamp,
                level: entry.level,
                label: label.value,
                message: message.value,
                source: source.value,
                metadata: metadata.metadata
            )
        }
        return (sanitized, redactionCount)
    }

    private func environmentText(build: BuildMetadata) -> String {
        var lines = [
            "- Sloppy version: \(build.displayVersion)",
            "- Release build: \(build.isReleaseBuild ? "yes" : "no")",
            "- Deployment: \(build.deploymentKind.rawValue)",
            "- OS: \(processInfo.operatingSystemVersionString)"
        ]
        if let branch = build.git?.currentBranch, !branch.isEmpty {
            lines.append("- Git branch: \(branch)")
        }
        if let commit = build.git?.currentCommit, !commit.isEmpty {
            lines.append("- Git commit: \(commit)")
        }
        return lines.joined(separator: "\n")
    }

    private func formatLogs(_ entries: [SystemLogEntry]) -> String {
        guard !entries.isEmpty else {
            return "[no recent system logs]"
        }

        return entries.map { entry in
            var line = [
                timestampString(from: entry.timestamp),
                entry.level.rawValue.uppercased(),
                entry.label
            ].joined(separator: " ")
            if !entry.source.isEmpty {
                line += " [\(entry.source)]"
            }
            line += " \(entry.message)"
            if !entry.metadata.isEmpty {
                let metadata = entry.metadata
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: " ")
                line += " {\(metadata)}"
            }
            return line
        }.joined(separator: "\n")
    }

    private func timestampString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private func truncatedLogsText(_ logs: String, environment: String) -> String {
        var current = logs
        while current.count > 512 {
            current = String(current.prefix(max(512, current.count / 2)))
            let candidate = current + "\n...[truncated]"
            if makeIssueURL(environment: environment, logs: candidate).utf8.count <= Self.maxIssueURLBytes {
                return candidate
            }
        }
        return "[logs truncated: report URL length limit reached]"
    }

    private func makeIssueURL(environment: String, logs: String) -> String {
        var components = URLComponents(string: Self.issueBaseURL)
        components?.queryItems = [
            URLQueryItem(name: "template", value: Self.templateName),
            URLQueryItem(name: "title", value: "[Bug]: "),
            URLQueryItem(name: "summary", value: "Opened from Sloppy dashboard"),
            URLQueryItem(name: "environment", value: environment),
            URLQueryItem(name: "logs", value: logs)
        ]
        return components?.url?.absoluteString ?? Self.issueBaseURL
    }
}
