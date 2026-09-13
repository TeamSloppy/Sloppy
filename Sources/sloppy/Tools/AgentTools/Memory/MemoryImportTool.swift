import Foundation
import AnyLanguageModel
import Protocols

struct MemoryImportTool: CoreTool {
    let domain = "memory"
    let name = "memory.import"
    let title = "Import memory"
    let status = "fully_functional"
    let description = "Start, inspect or resume a durable, verified memory import for the current agent. Archives Markdown sources, processes every part in the background, independently reviews coverage, and saves/indexes records. Completion comes from job status, not an assistant response. Omit paths to import the current session's Markdown attachments."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "operation", description: "start, status, or resume", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "paths", description: "For start: Markdown file paths, or directories containing Markdown files. Omit to use this session's attachments.", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)), isOptional: true),
            .init(name: "job_id", description: "For status or resume: the job ID returned by start.", schema: DynamicGenerationSchema(type: String.self), isOptional: true)
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let service = context.memoryImportService else {
            return toolFailure(tool: name, code: "not_available", message: "Memory import service is unavailable.", retryable: false)
        }
        do {
            let job: MemoryImportJob
            switch arguments["operation"]?.asString ?? "start" {
            case "status", "resume":
                guard let id = arguments["job_id"]?.asString, !id.isEmpty else { throw MemoryImportError.invalid("job_id is required.") }
                job = arguments["operation"]?.asString == "status"
                    ? try await service.getMemoryImport(agentID: context.agentID, id: id)
                    : try await service.resumeMemoryImport(agentID: context.agentID, id: id)
            case "start":
                if let paths = arguments["paths"], paths != .null, paths.asArray == nil { throw MemoryImportError.invalid("paths must be an array of file or directory paths.") }
                let rawPaths = arguments["paths"]?.asArray ?? []
                guard rawPaths.count <= 20 else { throw MemoryImportError.invalid("Provide at most 20 source paths.") }
                guard rawPaths.allSatisfy({ $0.asString != nil }) else { throw MemoryImportError.invalid("paths must contain strings.") }
                if rawPaths.isEmpty {
                    job = try await service.importSessionAttachments(agentID: context.agentID, sessionID: context.sessionID)
                } else {
                    let uploads = try readUploads(paths: rawPaths.compactMap(\.asString), context: context)
                    job = try await service.startMemoryImport(agentID: context.agentID, request: .init(sessionId: context.sessionID, attachments: uploads))
                }
            default: throw MemoryImportError.invalid("operation must be start, status, or resume.")
            }
            return toolSuccess(tool: name, data: Self.resultData(job))
        } catch {
            return toolFailure(tool: name, code: "memory_import_failed", message: error.localizedDescription, retryable: false,
                hint: "For an existing job, inspect its status and resume after resolving the reported error. Do not substitute a partial manual import.")
        }
    }

    static func resultData(_ job: MemoryImportJob) -> JSONValue {
        .object([
            "job_id": .string(job.id), "status": .string(job.status.rawValue), "agent_id": .string(job.agentId),
            "session_id": .string(job.sessionId), "completed_units": .number(Double(job.completedUnits)),
            "total_units": .number(Double(job.totalUnits)), "saved_count": .number(Double(job.savedCount)),
            "duplicate_count": .number(Double(job.duplicateCount)), "ignored_count": .number(Double(job.ignoredCount)),
            "error": job.error.map { .string(String($0.prefix(2000))) } ?? .null,
            "sources": .array(job.sources.map { .object(["id": .string($0.id), "name": .string(String($0.name.prefix(128))), "completed_units": .number(Double($0.completedUnits)), "total_units": .number(Double($0.totalUnits))]) })
        ])
    }

    private func readUploads(paths: [String], context: ToolContext) throws -> [AgentAttachmentUpload] {
        var files: [URL] = []
        for path in paths {
            guard let url = context.resolveReadablePath(path) else { throw MemoryImportError.invalid("Source path is outside allowed roots.") }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { throw MemoryImportError.invalid("Could not read the source directory.") }
                for case let child as URL in walker where ["md", "markdown"].contains(child.pathExtension.lowercased()) {
                    guard let readable = context.resolveReadablePath(child.path) else { throw MemoryImportError.invalid("A source is outside allowed roots.") }
                    files.append(readable)
                    guard files.count <= 20 else { throw MemoryImportError.invalid("Import at most 20 Markdown files at a time.") }
                }
            } else { files.append(url) }
        }
        let unique = Array(Set(files)).sorted { $0.path < $1.path }
        guard unique.count <= 20 else { throw MemoryImportError.invalid("Import at most 20 Markdown files at a time.") }
        return try unique.map { url -> AgentAttachmentUpload in
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 1024 * 1024 else { throw MemoryImportError.invalid("Each Markdown source must be a regular file up to 1 MB.") }
            let data = try Data(contentsOf: url)
            return .init(name: url.lastPathComponent, mimeType: "text/markdown", sizeBytes: data.count, contentBase64: data.base64EncodedString())
        }
    }

}
