import AnyLanguageModel
import Foundation
import Protocols

struct SitesListTool: CoreTool {
    let domain = "sites"
    let title = "List published sites"
    let status = "fully_functional"
    let name = "sites.list"
    let description = "List static sites published by the current Sloppy user."

    var parameters: GenerationSchema { .objectSchema([]) }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let service = context.siteService else {
            return siteToolUnavailable(name)
        }
        let principal = SiteAccessPrincipal(id: siteOwnerID(context), isAdmin: false)
        let response = await service.listPublishedSites(principal: principal)
        return toolSuccess(
            tool: name,
            data: .object(["sites": .array(response.sites.map(siteJSON))])
        )
    }
}

struct SitesPublishTool: CoreTool {
    let domain = "sites"
    let title = "Publish static site"
    let status = "fully_functional"
    let name = "sites.publish"
    let description = "Publish a validated static build directory at /sites/<slug>/, or atomically replace an existing site bundle."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "sourcePath", description: "Path to the completed static build directory.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "slug", description: "URL slug using lowercase letters, digits, and hyphens.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "title", description: "Human-readable site title.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "siteId", description: "Existing site id to update atomically.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "entryFile", description: "Entry file relative to sourcePath. Defaults to index.html.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "visibility", description: "private (default) or public.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "confirmedPublic", description: "Must be true when publishing publicly.", schema: DynamicGenerationSchema(type: Bool.self), isOptional: true),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let service = context.siteService else { return siteToolUnavailable(name) }
        guard let rawPath = arguments["sourcePath"]?.asString,
              let sourceURL = context.resolveReadablePath(rawPath),
              let slug = arguments["slug"]?.asString,
              let title = arguments["title"]?.asString
        else {
            return toolFailure(
                tool: name,
                code: "invalid_arguments",
                message: "`sourcePath`, `slug`, and `title` are required and sourcePath must be readable.",
                retryable: false
            )
        }
        let visibility: PublishedSiteVisibility
        switch arguments["visibility"]?.asString?.lowercased() ?? "private" {
        case "private": visibility = .private
        case "public":
            guard arguments["confirmedPublic"]?.asBool == true else {
                return toolFailure(
                    tool: name,
                    code: "confirmation_required",
                    message: "Publishing a site publicly requires explicit confirmation.",
                    retryable: false
                )
            }
            visibility = .public
        default:
            return toolFailure(tool: name, code: "invalid_arguments", message: "visibility must be private or public.", retryable: false)
        }

        do {
            let site = try await service.publishSite(
                sourceURL: sourceURL,
                siteID: arguments["siteId"]?.asString,
                slug: slug,
                title: title,
                visibility: visibility,
                ownerID: siteOwnerID(context),
                projectID: context.currentProjectID,
                entryFile: arguments["entryFile"]?.asString ?? "index.html"
            )
            return toolSuccess(tool: name, data: .object(["site": siteJSON(site)]))
        } catch {
            return siteToolFailure(name, error)
        }
    }
}

struct SitesUpdateTool: CoreTool {
    let domain = "sites"
    let title = "Update published site"
    let status = "fully_functional"
    let name = "sites.update"
    let description = "Update the title, slug, or private/public visibility of an owned published site."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "siteId", description: "Published site id.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "title", description: "New site title.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "slug", description: "New URL slug.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "visibility", description: "private or public.", schema: DynamicGenerationSchema(type: String.self), isOptional: true),
            .init(name: "confirmedPublic", description: "Must be true when changing visibility to public.", schema: DynamicGenerationSchema(type: Bool.self), isOptional: true),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let service = context.siteService else { return siteToolUnavailable(name) }
        guard let siteID = arguments["siteId"]?.asString, !siteID.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`siteId` is required.", retryable: false)
        }
        var visibility: PublishedSiteVisibility?
        if let raw = arguments["visibility"]?.asString?.lowercased() {
            guard let parsed = PublishedSiteVisibility(rawValue: raw) else {
                return toolFailure(tool: name, code: "invalid_arguments", message: "visibility must be private or public.", retryable: false)
            }
            if parsed == .public, arguments["confirmedPublic"]?.asBool != true {
                return toolFailure(tool: name, code: "confirmation_required", message: "Public visibility requires explicit confirmation.", retryable: false)
            }
            visibility = parsed
        }
        let request = PublishedSiteUpdateRequest(
            title: arguments["title"]?.asString,
            slug: arguments["slug"]?.asString,
            visibility: visibility
        )
        guard request.title != nil || request.slug != nil || request.visibility != nil else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "Provide title, slug, or visibility.", retryable: false)
        }
        do {
            let site = try await service.updatePublishedSite(
                id: siteID,
                request: request,
                principal: SiteAccessPrincipal(id: siteOwnerID(context), isAdmin: false)
            )
            return toolSuccess(tool: name, data: .object(["site": siteJSON(site)]))
        } catch {
            return siteToolFailure(name, error)
        }
    }
}

struct SitesDeleteTool: CoreTool {
    let domain = "sites"
    let title = "Delete published site"
    let status = "fully_functional"
    let name = "sites.delete"
    let description = "Permanently delete an owned published site and its deployed bundle."

    var parameters: GenerationSchema {
        .objectSchema([
            .init(name: "siteId", description: "Published site id.", schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "confirmed", description: "Must be true after explicit user confirmation.", schema: DynamicGenerationSchema(type: Bool.self)),
        ])
    }

    func invoke(arguments: [String: JSONValue], context: ToolContext) async -> ToolInvocationResult {
        guard let service = context.siteService else { return siteToolUnavailable(name) }
        guard let siteID = arguments["siteId"]?.asString, !siteID.isEmpty else {
            return toolFailure(tool: name, code: "invalid_arguments", message: "`siteId` is required.", retryable: false)
        }
        guard arguments["confirmed"]?.asBool == true else {
            return toolFailure(tool: name, code: "confirmation_required", message: "Deleting a published site requires explicit confirmation.", retryable: false)
        }
        do {
            try await service.deletePublishedSite(
                id: siteID,
                principal: SiteAccessPrincipal(id: siteOwnerID(context), isAdmin: false)
            )
            return toolSuccess(tool: name, data: .object(["deleted": .bool(true), "siteId": .string(siteID)]))
        } catch {
            return siteToolFailure(name, error)
        }
    }
}

private func siteOwnerID(_ context: ToolContext) -> String {
    let value = context.userID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? "local" : value
}

private func siteJSON(_ site: PublishedSiteRecord) -> JSONValue {
    .object([
        "id": .string(site.id),
        "slug": .string(site.slug),
        "title": .string(site.title),
        "visibility": .string(site.visibility.rawValue),
        "ownerId": .string(site.ownerId),
        "projectId": site.projectId.map(JSONValue.string) ?? .null,
        "entryFile": .string(site.entryFile),
        "revision": .number(Double(site.revision)),
        "path": .string(site.path),
        "createdAt": .string(ISO8601DateFormatter().string(from: site.createdAt)),
        "updatedAt": .string(ISO8601DateFormatter().string(from: site.updatedAt)),
    ])
}

private func siteToolUnavailable(_ tool: String) -> ToolInvocationResult {
    toolFailure(tool: tool, code: "unavailable", message: "Published sites service is unavailable.", retryable: true)
}

private func siteToolFailure(_ tool: String, _ error: Error) -> ToolInvocationResult {
    guard let error = error as? PublishedSiteService.SiteError else {
        return toolFailure(tool: tool, code: "site_operation_failed", message: "The site operation failed.", retryable: true)
    }
    switch error {
    case .notFound:
        return toolFailure(tool: tool, code: "not_found", message: "Published site was not found.", retryable: false)
    case .forbidden:
        return toolFailure(tool: tool, code: "permission_denied", message: "The current user does not own this site.", retryable: false)
    case .slugConflict:
        return toolFailure(tool: tool, code: "slug_conflict", message: "Another published site already uses this slug.", retryable: false)
    case .invalidSlug:
        return toolFailure(tool: tool, code: "invalid_arguments", message: "Slug must contain lowercase letters, digits, and single hyphens.", retryable: false)
    case .invalidTitle:
        return toolFailure(tool: tool, code: "invalid_arguments", message: "Title is empty or too long.", retryable: false)
    case .invalidEntryFile:
        return toolFailure(tool: tool, code: "invalid_bundle", message: "The entry file is missing or unsafe.", retryable: false)
    case .invalidSource:
        return toolFailure(tool: tool, code: "invalid_bundle", message: "sourcePath must be a readable build directory outside .sloppy/sites.", retryable: false)
    case .forbiddenSourceEntry(let path):
        return toolFailure(tool: tool, code: "forbidden_bundle_entry", message: "The bundle contains a forbidden or symbolic-link entry: \(path)", retryable: false)
    case .bundleTooLarge:
        return toolFailure(tool: tool, code: "bundle_too_large", message: "The static bundle exceeds the configured size limit.", retryable: false)
    case .tooManyFiles:
        return toolFailure(tool: tool, code: "too_many_files", message: "The static bundle exceeds the configured file-count limit.", retryable: false)
    case .storageFailure:
        return toolFailure(tool: tool, code: "storage_failure", message: "Could not store the published site bundle.", retryable: true)
    }
}
