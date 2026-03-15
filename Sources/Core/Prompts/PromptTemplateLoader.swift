import Foundation

struct PromptTemplateLoader {
    enum LoaderError: Error, Equatable {
        case templateNotFound(String)
        case unreadableTemplate(String)
    }

    typealias Resolver = @Sendable (_ relativePath: String) throws -> String

    private let resolver: Resolver

    init(bundle: Bundle = .module, basePath: String = "Prompts/en") {
        self.resolver = { relativePath in
            let nsPath = relativePath as NSString
            let resourcePath = nsPath.deletingPathExtension
            let resourceExtension = nsPath.pathExtension.isEmpty ? nil : nsPath.pathExtension
            let subdirectoryPath = (basePath as NSString).appendingPathComponent(nsPath.deletingLastPathComponent)
            let normalizedSubdirectory = subdirectoryPath.hasSuffix("/")
                ? String(subdirectoryPath.dropLast())
                : subdirectoryPath
            let effectiveSubdirectory = nsPath.deletingLastPathComponent.isEmpty ? basePath : normalizedSubdirectory

            let resourceName = (resourcePath as NSString).lastPathComponent
            let candidates: [URL?] = [
                bundle.url(
                    forResource: resourceName,
                    withExtension: resourceExtension,
                    subdirectory: effectiveSubdirectory
                ),
                bundle.url(
                    forResource: resourceName,
                    withExtension: resourceExtension
                ),
                bundle.resourceURL?.appendingPathComponent(basePath).appendingPathComponent(relativePath),
                bundle.resourceURL?.appendingPathComponent(relativePath),
                bundle.resourceURL?.appendingPathComponent(resourceName + (resourceExtension.map { ".\($0)" } ?? ""))
            ]

            guard let url = candidates.compactMap({ $0 }).first(where: {
                FileManager.default.fileExists(atPath: $0.path)
            }) else {
                throw LoaderError.templateNotFound(relativePath)
            }

            do {
                return try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw LoaderError.unreadableTemplate(relativePath)
            }
        }
    }

    init(resolver: @escaping Resolver) {
        self.resolver = resolver
    }

    func loadTemplate(for processKind: PromptProcessKind) throws -> String {
        try resolver("\(processKind.templateName).md")
    }

    func loadPartial(named name: String) throws -> String {
        try resolver("partials/\(name).md")
    }
}
