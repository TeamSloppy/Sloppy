import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging
import Protocols

enum AgentPluginManagerError: Error, LocalizedError, Sendable {
    case archiveTooLarge
    case archiveInvalid(String)
    case sourceInvalid(String)
    case manifestInvalid(String)
    case incompatible(String)
    case notFound(String)
    case expired
    case approvalRequired(String)
    case conflict(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .archiveTooLarge: "Agent Plugin ZIP exceeds the 100 MiB upload limit."
        case .archiveInvalid(let message): "Invalid Agent Plugin ZIP: \(message)"
        case .sourceInvalid(let message): "Invalid Agent Plugin source: \(message)"
        case .manifestInvalid(let message): "Invalid agent-plugin.json: \(message)"
        case .incompatible(let message): "Agent Plugin is incompatible: \(message)"
        case .notFound(let value): "Agent Plugin resource was not found: \(value)"
        case .expired: "The Agent Plugin inspection or plan expired. Inspect the package again."
        case .approvalRequired(let message): message
        case .conflict(let message): message
        case .commandFailed(let message): message
        }
    }
}

struct AgentPluginExecutionContext: Sendable {
    var plan: AgentPluginInstallPlan
    var inspection: AgentPluginInspection
    var packageURL: URL
    var inputs: [String: String]
}

private struct AgentPluginInspectionState: Sendable {
    var inspection: AgentPluginInspection
    var packageURL: URL
}

private struct AgentPluginPlanState: Sendable {
    var plan: AgentPluginInstallPlan
    var inspection: AgentPluginInspection
    var packageURL: URL
    var inputs: [String: String]
}

actor AgentPluginManager {
    static let officialRegistry = AgentPluginRegistry(
        id: "sloppy-official",
        name: "Sloppy Store",
        baseURL: "https://registry.sloppy.team",
        enabled: true,
        isDefault: true
    )

    private static let maximumArchiveBytes = 100 * 1_024 * 1_024
    private static let maximumExpandedBytes: UInt64 = 500 * 1_024 * 1_024
    private static let maximumEntries = 10_000
    private static let inspectionLifetime: TimeInterval = 15 * 60
    private static let uploadLifetime: TimeInterval = 60 * 60

    private var workspaceRootURL: URL
    private var store: any PersistenceStore
    private let fileManager: FileManager
    private let session: URLSession
    private let logger: Logger
    private var inspections: [String: AgentPluginInspectionState] = [:]
    private var plans: [String: AgentPluginPlanState] = [:]
    private var operations: [String: AgentPluginOperation] = [:]

    init(
        workspaceRootURL: URL,
        store: any PersistenceStore,
        fileManager: FileManager = .default,
        session: URLSession = .shared,
        logger: Logger = Logger.sloppy(label: "sloppy.agent-plugins")
    ) {
        self.workspaceRootURL = workspaceRootURL
        self.store = store
        self.fileManager = fileManager
        self.session = session
        self.logger = logger
    }

    func update(workspaceRootURL: URL, store: any PersistenceStore) {
        self.workspaceRootURL = workspaceRootURL
        self.store = store
        inspections.removeAll()
        plans.removeAll()
    }

    func listInstalled() async -> [InstalledAgentPlugin] { await store.listAgentPlugins() }
    func installed(id: String) async -> InstalledAgentPlugin? { await store.agentPlugin(id: id) }

    func upload(_ data: Data) throws -> AgentPluginUpload {
        try purgeExpiredStaging()
        guard !data.isEmpty, data.count <= Self.maximumArchiveBytes else { throw AgentPluginManagerError.archiveTooLarge }
        _ = try AgentPluginArchive.validate(data: data)
        let id = UUID().uuidString.lowercased()
        let expiresAt = Date().addingTimeInterval(Self.uploadLifetime)
        let url = uploadsRootURL.appendingPathComponent("\(id).zip")
        try fileManager.createDirectory(at: uploadsRootURL, withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
        return AgentPluginUpload(id: id, sha256: AgentPluginSHA256.hash(data), size: Int64(data.count), expiresAt: expiresAt)
    }

    func inspect(_ request: AgentPluginInspectionRequest) async throws -> AgentPluginInspection {
        try purgeExpiredStaging()
        let resolved = try await resolveArchive(for: request.source)
        let entries = try AgentPluginArchive.validate(data: resolved.data)
        guard entries.contains(where: { $0.path == "agent-plugin.json" }) else {
            throw AgentPluginManagerError.archiveInvalid("agent-plugin.json must be at the ZIP root")
        }

        let id = UUID().uuidString.lowercased()
        let inspectionRoot = inspectionsRootURL.appendingPathComponent(id, isDirectory: true)
        let archiveURL = inspectionRoot.appendingPathComponent("package.zip")
        let packageURL = inspectionRoot.appendingPathComponent("package", isDirectory: true)
        try fileManager.createDirectory(at: inspectionRoot, withIntermediateDirectories: true)
        try resolved.data.write(to: archiveURL, options: [.atomic])
        do {
            try await AgentPluginArchive.extract(archiveURL: archiveURL, destinationURL: packageURL)
        } catch {
            try? fileManager.removeItem(at: inspectionRoot)
            throw error
        }

        let manifestURL = packageURL.appendingPathComponent("agent-plugin.json")
        let manifest: AgentPluginManifest
        do {
            manifest = try JSONDecoder().decode(AgentPluginManifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw AgentPluginManagerError.manifestInvalid(error.localizedDescription)
        }
        try validate(manifest: manifest, packageURL: packageURL)

        let sha256 = AgentPluginSHA256.hash(resolved.data)
        if let expected = resolved.expectedSHA256?.lowercased(), expected != sha256 {
            throw AgentPluginManagerError.archiveInvalid("SHA-256 mismatch; expected \(expected), received \(sha256)")
        }
        let trust: AgentPluginInspection.Trust = resolved.expectedSHA256 == nil ? .unverified : .verifiedChecksum
        let inspection = AgentPluginInspection(
            id: id,
            source: request.source,
            manifest: manifest,
            sha256: sha256,
            size: Int64(resolved.data.count),
            trust: trust,
            warnings: trust == .unverified ? ["This ZIP has no registry checksum. Confirm that you trust its source."] : [],
            expiresAt: Date().addingTimeInterval(Self.inspectionLifetime)
        )
        inspections[id] = AgentPluginInspectionState(inspection: inspection, packageURL: packageURL)
        return inspection
    }

    func makePlan(_ request: AgentPluginPlanRequest, availableAgentIDs: Set<String>) throws -> AgentPluginInstallPlan {
        purgeExpiredEphemeralState()
        guard let state = inspections[request.inspectionId], state.inspection.expiresAt > Date() else {
            throw AgentPluginManagerError.expired
        }
        let manifest = state.inspection.manifest
        let agents = Array(Set(request.agentIds)).sorted()
        if !manifest.components.skills.isEmpty {
            guard !agents.isEmpty else { throw AgentPluginManagerError.manifestInvalid("Select at least one agent for packaged skills") }
            let missing = agents.filter { !availableAgentIDs.contains($0) }
            guard missing.isEmpty else { throw AgentPluginManagerError.notFound("agents \(missing.joined(separator: ", "))") }
        }
        try validateInputs(manifest.inputs, values: request.inputs)
        var resolvedInputs = request.inputs
        for definition in manifest.inputs where resolvedInputs[definition.id] == nil {
            if let defaultValue = definition.defaultValue { resolvedInputs[definition.id] = defaultValue }
        }

        var changes: [AgentPluginPlannedChange] = []
        for skill in manifest.components.skills {
            changes.append(.init(id: "skill:\(skill.id)", kind: .skill, title: skill.id, detail: "Install for \(agents.count) selected agent(s)"))
        }
        for mcp in manifest.components.mcpServers {
            changes.append(.init(id: "mcp:\(mcp.id)", kind: .mcp, title: mcp.id, detail: "Add namespaced \(mcp.transport) MCP server"))
        }
        for plugin in manifest.components.sloppyPlugins {
            changes.append(.init(id: "plugin:\(plugin.id)", kind: .sloppyPlugin, title: plugin.id, detail: "Install Sloppy source plugin"))
        }
        let software = compatibleSoftware(in: manifest)
        for item in software {
            changes.append(.init(id: "software:\(item.id)", kind: .software, title: item.id, detail: "Run \(item.install.count) approved install step(s)"))
        }
        let commands = software.flatMap(\.install)
        let planID = UUID().uuidString.lowercased()
        let expiresAt = Date().addingTimeInterval(Self.inspectionLifetime)
        let approvalMaterial = [manifest.id, manifest.version, state.inspection.sha256, agents.joined(separator: ","), resolvedInputs.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&"), commands.map(\.id).joined(separator: ",")].joined(separator: "|")
        let approvalHash = AgentPluginSHA256.hash(Data(approvalMaterial.utf8))
        let plan = AgentPluginInstallPlan(
            id: planID,
            inspectionId: request.inspectionId,
            packageId: manifest.id,
            version: manifest.version,
            sha256: state.inspection.sha256,
            agentIds: agents,
            changes: changes,
            commands: commands,
            warnings: state.inspection.warnings,
            requiresTrustConfirmation: state.inspection.trust == .unverified,
            requiresCommandApproval: !commands.isEmpty,
            approvalHash: approvalHash,
            expiresAt: expiresAt
        )
        plans[planID] = AgentPluginPlanState(plan: plan, inspection: state.inspection, packageURL: state.packageURL, inputs: resolvedInputs)
        return plan
    }

    func consumePlan(_ request: AgentPluginInstallRequest) throws -> AgentPluginExecutionContext {
        purgeExpiredEphemeralState()
        guard let state = plans.removeValue(forKey: request.planId), state.plan.expiresAt > Date() else {
            throw AgentPluginManagerError.expired
        }
        guard request.approvalHash == state.plan.approvalHash else {
            throw AgentPluginManagerError.approvalRequired("The install plan changed. Review it again before installing.")
        }
        if state.plan.requiresTrustConfirmation && !request.trustConfirmed {
            throw AgentPluginManagerError.approvalRequired("Confirm that you trust this unverified ZIP source.")
        }
        if state.plan.requiresCommandApproval && !request.commandsApproved {
            throw AgentPluginManagerError.approvalRequired("Approve the declared software commands before installing.")
        }
        return AgentPluginExecutionContext(plan: state.plan, inspection: state.inspection, packageURL: state.packageURL, inputs: state.inputs)
    }

    func beginOperation(packageId: String, kind: AgentPluginOperation.Kind, message: String) -> AgentPluginOperation {
        let operation = AgentPluginOperation(id: UUID().uuidString.lowercased(), packageId: packageId, kind: kind, status: .running, progress: 0, message: message, startedAt: Date(), finishedAt: nil)
        operations[operation.id] = operation
        return operation
    }

    func updateOperation(id: String, status: AgentPluginOperation.Status? = nil, progress: Double? = nil, message: String? = nil) {
        guard var operation = operations[id] else { return }
        if let status { operation.status = status }
        if let progress { operation.progress = min(1, max(0, progress)) }
        if let message { operation.message = message }
        if operation.status == .completed || operation.status == .failed || operation.status == .failedWithResiduals { operation.finishedAt = Date() }
        operations[id] = operation
    }

    func operation(id: String) -> AgentPluginOperation? { operations[id] }

    func discardInspection(id: String) {
        inspections[id] = nil
        let url = inspectionsRootURL.appendingPathComponent(id, isDirectory: true)
        try? fileManager.removeItem(at: url)
    }

    func listRegistries() async -> [AgentPluginRegistry] {
        let existing = await store.listAgentPluginRegistries()
        if existing.isEmpty {
            await store.saveAgentPluginRegistry(Self.officialRegistry)
            return [Self.officialRegistry]
        }
        return existing
    }

    func saveRegistry(id: String?, request: AgentPluginRegistryWriteRequest) async throws -> AgentPluginRegistry {
        guard let url = URL(string: request.baseURL), url.scheme?.lowercased() == "https", url.host != nil else {
            throw AgentPluginManagerError.sourceInvalid("Registry URL must be an absolute HTTPS URL")
        }
        let registry = AgentPluginRegistry(id: id ?? UUID().uuidString.lowercased(), name: request.name.trimmingCharacters(in: .whitespacesAndNewlines), baseURL: url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")), enabled: request.enabled, isDefault: request.isDefault)
        guard !registry.name.isEmpty else { throw AgentPluginManagerError.sourceInvalid("Registry name is required") }
        await store.saveAgentPluginRegistry(registry)
        return registry
    }

    func deleteRegistry(id: String) async throws {
        guard id != Self.officialRegistry.id else { throw AgentPluginManagerError.conflict("The official registry can be disabled but not deleted.") }
        await store.deleteAgentPluginRegistry(id: id)
    }

    func catalog(search: String, registryID: String?, cursor: String?, limit: Int) async -> AgentPluginCatalogResponse {
        let registries = await listRegistries().filter { $0.enabled && (registryID == nil || $0.id == registryID) }
        var packages: [AgentPluginCatalogItem] = []
        var warnings: [String] = []
        for registry in registries {
            do {
                var components = URLComponents(string: registry.baseURL + "/v1/packages")
                components?.queryItems = [
                    URLQueryItem(name: "query", value: search.isEmpty ? nil : search),
                    URLQueryItem(name: "cursor", value: cursor),
                    URLQueryItem(name: "limit", value: String(max(1, min(limit, 100)))),
                ].filter { $0.value != nil }
                guard let url = components?.url else { throw AgentPluginManagerError.sourceInvalid(registry.baseURL) }
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AgentPluginManagerError.sourceInvalid("registry returned an error") }
                var decoded = try JSONDecoder().decode(AgentPluginCatalogResponse.self, from: data)
                for index in decoded.packages.indices { decoded.packages[index].registryId = registry.id }
                packages.append(contentsOf: decoded.packages)
                warnings.append(contentsOf: decoded.warnings)
            } catch {
                warnings.append("\(registry.name): \(error.localizedDescription)")
            }
        }
        packages.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return AgentPluginCatalogResponse(packages: packages, nextCursor: nil, warnings: warnings)
    }

    func packageInstallURL(_ packageID: String, version: String) -> URL {
        packagesRootURL.appendingPathComponent(packageID, isDirectory: true).appendingPathComponent(version, isDirectory: true)
    }

    func hashTree(_ url: URL) throws -> String {
        var data = Data()
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            let files = enumerator.compactMap { $0 as? URL }.sorted { $0.path < $1.path }
            for file in files {
                let values = try file.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                data.append(Data(file.path.replacingOccurrences(of: url.path, with: "").utf8))
                data.append(try Data(contentsOf: file))
            }
        } else {
            data = try Data(contentsOf: url)
        }
        return AgentPluginSHA256.hash(data)
    }

    func render(_ value: String, inputs: [String: String], packageID: String) throws -> String {
        var rendered = value
        for (key, input) in inputs { rendered = rendered.replacingOccurrences(of: "${input.\(key)}", with: input) }
        for input in inputs where rendered.contains("${secret.\(input.key)}") {
            rendered = rendered.replacingOccurrences(of: "${secret.\(input.key)}", with: input.value)
        }
        if rendered.contains("${input.") || rendered.contains("${secret.") {
            throw AgentPluginManagerError.manifestInvalid("Unresolved template in \(packageID)")
        }
        return rendered
    }

    func run(_ commands: [AgentPluginCommand], packageURL: URL, inputs: [String: String], packageID: String) async throws {
        for command in commands {
            let executable = try render(command.executable, inputs: inputs, packageID: packageID)
            let arguments = try command.arguments.map { try render($0, inputs: inputs, packageID: packageID) }
            let environment = try command.environment.reduce(into: [String: String]()) { output, pair in
                output[pair.key] = try render(pair.value, inputs: inputs, packageID: packageID)
            }
            let cwd: URL
            if let relative = command.cwd {
                cwd = try safeComponentURL(relative, root: packageURL)
            } else {
                cwd = packageURL
            }
            let result = try await AgentPluginCommandRunner.run(executable: executable, arguments: arguments, cwd: cwd, environment: environment, timeoutSeconds: command.timeoutSeconds)
            guard result.exitCode == 0 else {
                throw AgentPluginManagerError.commandFailed("Command \(command.id) failed with exit \(result.exitCode): \(redact(result.output, secrets: Array(inputs.values)))")
            }
        }
    }

    func safeComponentURL(_ relativePath: String, root: URL) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), !relativePath.contains("\\") else { throw AgentPluginManagerError.manifestInvalid("Invalid component path: \(relativePath)") }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(".."), !components.contains("") else { throw AgentPluginManagerError.manifestInvalid("Invalid component path: \(relativePath)") }
        let rootPath = root.standardizedFileURL.path
        let url = root.appendingPathComponent(relativePath).standardizedFileURL
        guard url.path.hasPrefix(rootPath + "/"), fileManager.fileExists(atPath: url.path) else { throw AgentPluginManagerError.manifestInvalid("Missing component path: \(relativePath)") }
        return url
    }

    private var rootURL: URL { workspaceRootURL.appendingPathComponent("agent-plugins", isDirectory: true) }
    private var uploadsRootURL: URL { rootURL.appendingPathComponent("uploads", isDirectory: true) }
    private var inspectionsRootURL: URL { rootURL.appendingPathComponent("inspections", isDirectory: true) }
    private var packagesRootURL: URL { rootURL.appendingPathComponent("packages", isDirectory: true) }

    private func resolveArchive(for source: AgentPluginSource) async throws -> (data: Data, expectedSHA256: String?) {
        switch source.kind {
        case .upload:
            guard let id = source.uploadId, !id.isEmpty else { throw AgentPluginManagerError.sourceInvalid("uploadId is required") }
            let url = uploadsRootURL.appendingPathComponent("\(id).zip")
            guard fileManager.fileExists(atPath: url.path) else { throw AgentPluginManagerError.notFound(id) }
            return (try Data(contentsOf: url), source.expectedSHA256)
        case .url:
            guard let value = source.url, let url = URL(string: value), url.scheme?.lowercased() == "https" else { throw AgentPluginManagerError.sourceInvalid("Only HTTPS download URLs are accepted") }
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AgentPluginManagerError.sourceInvalid("Download failed") }
            guard data.count <= Self.maximumArchiveBytes else { throw AgentPluginManagerError.archiveTooLarge }
            return (data, source.expectedSHA256)
        case .registry:
            guard let registryID = source.registryId, let packageID = source.packageId, let version = source.version else { throw AgentPluginManagerError.sourceInvalid("registryId, packageId, and version are required") }
            guard let registry = await listRegistries().first(where: { $0.id == registryID && $0.enabled }) else { throw AgentPluginManagerError.notFound(registryID) }
            let parts = packageID.split(separator: ".", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { throw AgentPluginManagerError.sourceInvalid("Package ID must be scope.name") }
            let metadataURL = URL(string: registry.baseURL + "/v1/packages/\(parts[0])/\(parts[1])")!
            let (metadataData, metadataResponse) = try await session.data(from: metadataURL)
            guard let http = metadataResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AgentPluginManagerError.sourceInvalid("Registry metadata request failed") }
            var item = try JSONDecoder().decode(AgentPluginCatalogItem.self, from: metadataData)
            item.registryId = registryID
            guard let release = item.releases.first(where: { $0.version == version }), let downloadURL = URL(string: release.downloadURL), downloadURL.scheme?.lowercased() == "https" else { throw AgentPluginManagerError.notFound("\(packageID) \(version)") }
            let (data, response) = try await session.data(from: downloadURL)
            guard let download = response as? HTTPURLResponse, (200..<300).contains(download.statusCode), data.count <= Self.maximumArchiveBytes else { throw AgentPluginManagerError.sourceInvalid("Registry download failed") }
            return (data, release.sha256)
        }
    }

    private func validate(manifest: AgentPluginManifest, packageURL: URL) throws {
        guard manifest.schemaVersion == 1 else { throw AgentPluginManagerError.manifestInvalid("Unsupported schemaVersion \(manifest.schemaVersion)") }
        guard manifest.id.range(of: #"^[a-z0-9][a-z0-9-]*\.[a-z0-9][a-z0-9._-]*$"#, options: .regularExpression) != nil else { throw AgentPluginManagerError.manifestInvalid("id must use scope.name") }
        guard AgentPluginSemanticVersion(manifest.version) != nil else { throw AgentPluginManagerError.manifestInvalid("version must be SemVer") }
        if let minimum = manifest.minimumSloppyVersion,
           let current = SloppyVersion.releaseVersion,
           SloppyVersion.isNewer(minimum, than: current) {
            throw AgentPluginManagerError.incompatible("requires Sloppy \(minimum) or newer; Core is \(current)")
        }
        if !manifest.platforms.isEmpty && !matchesCurrentPlatform(manifest.platforms) { throw AgentPluginManagerError.incompatible("no matching OS/architecture") }
        let ids = manifest.components.skills.map(\.id) + manifest.components.mcpServers.map(\.id) + manifest.components.sloppyPlugins.map(\.id) + manifest.components.software.map(\.id)
        guard ids.count == Set(ids).count else { throw AgentPluginManagerError.manifestInvalid("component IDs must be unique") }
        for component in manifest.components.skills { _ = try safeComponentURL(component.path, root: packageURL) }
        for component in manifest.components.sloppyPlugins { _ = try safeComponentURL(component.path, root: packageURL) }
        for component in manifest.components.software where component.uninstall.isEmpty || component.rollback.isEmpty {
            throw AgentPluginManagerError.manifestInvalid("software component \(component.id) requires uninstall and rollback steps")
        }
        for component in manifest.components.software {
            for command in component.uninstall where commandContainsSecretTemplate(command) {
                throw AgentPluginManagerError.manifestInvalid("uninstall command \(command.id) cannot require a non-persisted secret input")
            }
        }
    }

    private func validateInputs(_ definitions: [AgentPluginInput], values: [String: String]) throws {
        let known = Set(definitions.map(\.id))
        let unknown = values.keys.filter { !known.contains($0) }
        guard unknown.isEmpty else { throw AgentPluginManagerError.manifestInvalid("Unknown input(s): \(unknown.sorted().joined(separator: ", "))") }
        for definition in definitions {
            let value = values[definition.id] ?? definition.defaultValue ?? ""
            if definition.required && value.isEmpty { throw AgentPluginManagerError.manifestInvalid("Input \(definition.id) is required") }
            if definition.kind == .choice && !value.isEmpty && !definition.choices.contains(value) { throw AgentPluginManagerError.manifestInvalid("Input \(definition.id) must be one of its declared choices") }
            if definition.kind == .boolean && !value.isEmpty && value != "true" && value != "false" { throw AgentPluginManagerError.manifestInvalid("Input \(definition.id) must be true or false") }
        }
    }

    private func compatibleSoftware(in manifest: AgentPluginManifest) -> [AgentPluginSoftwareComponent] {
        manifest.components.software.filter { $0.platforms.isEmpty || matchesCurrentPlatform($0.platforms) }
    }

    private func commandContainsSecretTemplate(_ command: AgentPluginCommand) -> Bool {
        ([command.executable] + command.arguments + Array(command.environment.values) + [command.cwd].compactMap { $0 })
            .contains { $0.contains("${secret.") }
    }

    private func matchesCurrentPlatform(_ platforms: [AgentPluginPlatform]) -> Bool {
#if os(macOS)
        let currentOS = "macos"
#elseif os(Linux)
        let currentOS = "linux"
#else
        let currentOS = "unsupported"
#endif
#if arch(arm64)
        let currentArchitecture = "arm64"
#elseif arch(x86_64)
        let currentArchitecture = "x86_64"
#else
        let currentArchitecture = "unknown"
#endif
        return platforms.contains { $0.os.lowercased() == currentOS && ($0.architectures.isEmpty || $0.architectures.map { $0.lowercased() }.contains(currentArchitecture)) }
    }

    private func purgeExpiredEphemeralState() {
        let now = Date()
        let expiredInspectionIDs = inspections.compactMap { $0.value.inspection.expiresAt <= now ? $0.key : nil }
        for id in expiredInspectionIDs {
            try? fileManager.removeItem(at: inspectionsRootURL.appendingPathComponent(id, isDirectory: true))
        }
        inspections = inspections.filter { $0.value.inspection.expiresAt > now }
        plans = plans.filter { $0.value.plan.expiresAt > now }
    }

    private func purgeExpiredStaging() throws {
        purgeExpiredEphemeralState()
        guard fileManager.fileExists(atPath: uploadsRootURL.path) else { return }
        let urls = try fileManager.contentsOfDirectory(at: uploadsRootURL, includingPropertiesForKeys: [.contentModificationDateKey])
        for url in urls {
            let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(modified) > Self.uploadLifetime { try? fileManager.removeItem(at: url) }
        }
    }

    private func redact(_ value: String, secrets: [String]) -> String {
        secrets.filter { !$0.isEmpty }.reduce(value) { $0.replacingOccurrences(of: $1, with: "[REDACTED]") }
    }
}

private struct AgentPluginSemanticVersion {
    init?(_ value: String) {
        guard value.range(of: #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$"#, options: .regularExpression) != nil else { return nil }
    }
}

private enum AgentPluginArchive {
    struct Entry { var path: String; var expandedSize: UInt64 }

    static func validate(data: Data) throws -> [Entry] {
        guard data.count <= 100 * 1_024 * 1_024 else { throw AgentPluginManagerError.archiveTooLarge }
        let bytes = [UInt8](data)
        guard let eocd = findEOCD(bytes) else { throw AgentPluginManagerError.archiveInvalid("missing ZIP central directory") }
        let count = Int(read16(bytes, eocd + 10))
        let centralOffset = Int(read32(bytes, eocd + 16))
        guard count <= 10_000, centralOffset >= 0, centralOffset < bytes.count else { throw AgentPluginManagerError.archiveInvalid("too many entries or invalid central directory") }
        var cursor = centralOffset
        var total: UInt64 = 0
        var seen = Set<String>()
        var entries: [Entry] = []
        for _ in 0..<count {
            guard cursor + 46 <= bytes.count, read32(bytes, cursor) == 0x02014b50 else { throw AgentPluginManagerError.archiveInvalid("invalid central directory entry") }
            let expanded = UInt64(read32(bytes, cursor + 24))
            let nameLength = Int(read16(bytes, cursor + 28))
            let extraLength = Int(read16(bytes, cursor + 30))
            let commentLength = Int(read16(bytes, cursor + 32))
            let externalAttributes = read32(bytes, cursor + 38)
            let nameStart = cursor + 46
            guard nameStart + nameLength <= bytes.count, let name = String(bytes: bytes[nameStart..<(nameStart + nameLength)], encoding: .utf8) else { throw AgentPluginManagerError.archiveInvalid("entry name is not UTF-8") }
            try validatePath(name)
            let unixType = (externalAttributes >> 16) & 0xF000
            if unixType == 0xA000 { throw AgentPluginManagerError.archiveInvalid("symbolic links are not allowed: \(name)") }
            if !seen.insert(name).inserted { throw AgentPluginManagerError.archiveInvalid("duplicate path: \(name)") }
            total += expanded
            guard total <= 500 * 1_024 * 1_024 else { throw AgentPluginManagerError.archiveInvalid("expanded contents exceed 500 MiB") }
            entries.append(Entry(path: name, expandedSize: expanded))
            cursor = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    static func extract(archiveURL: URL, destinationURL: URL) async throws {
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let result = try await AgentPluginCommandRunner.run(executable: "/usr/bin/env", arguments: ["unzip", "-qq", archiveURL.path, "-d", destinationURL.path], cwd: destinationURL, environment: [:], timeoutSeconds: 120)
        guard result.exitCode == 0 else { throw AgentPluginManagerError.archiveInvalid("unzip failed: \(result.output)") }
        try validateExtractedContents(at: destinationURL)
    }

    private static func validateExtractedContents(at destinationURL: URL) throws {
        guard let enumerator = FileManager.default.enumerator(at: destinationURL, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]) else { throw AgentPluginManagerError.archiveInvalid("cannot enumerate extracted contents") }
        var total: UInt64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
            if values.isSymbolicLink == true { throw AgentPluginManagerError.archiveInvalid("extracted symbolic link is not allowed") }
            if values.isRegularFile == true { total += UInt64(values.fileSize ?? 0) }
            guard total <= 500 * 1_024 * 1_024 else { throw AgentPluginManagerError.archiveInvalid("expanded contents exceed 500 MiB") }
        }
    }

    private static func validatePath(_ path: String) throws {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("\\"), !path.contains("\\"), !path.contains("\0") else { throw AgentPluginManagerError.archiveInvalid("unsafe path: \(path)") }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.contains("..") else { throw AgentPluginManagerError.archiveInvalid("path traversal: \(path)") }
    }

    private static func findEOCD(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        let lower = max(0, bytes.count - 65_557)
        for index in stride(from: bytes.count - 22, through: lower, by: -1) where read32(bytes, index) == 0x06054b50 { return index }
        return nil
    }

    private static func read16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset + 2 <= bytes.count else { return 0 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func read32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
}

enum AgentPluginSHA256 {
    static func hash(_ data: Data) -> String {
        let constants: [UInt32] = [0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2]
        var bytes = [UInt8](data)
        let bitLength = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0) }
        bytes.append(contentsOf: Swift.withUnsafeBytes(of: bitLength.bigEndian, Array.init))
        var h: [UInt32] = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19]
        for chunk in stride(from: 0, to: bytes.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 { let j = chunk + i * 4; w[i] = UInt32(bytes[j]) << 24 | UInt32(bytes[j+1]) << 16 | UInt32(bytes[j+2]) << 8 | UInt32(bytes[j+3]) }
            for i in 16..<64 { let s0 = rotate(w[i-15], 7) ^ rotate(w[i-15], 18) ^ (w[i-15] >> 3); let s1 = rotate(w[i-2], 17) ^ rotate(w[i-2], 19) ^ (w[i-2] >> 10); w[i] = w[i-16] &+ s0 &+ w[i-7] &+ s1 }
            var a=h[0],b=h[1],c=h[2],d=h[3],e=h[4],f=h[5],g=h[6],hh=h[7]
            for i in 0..<64 { let s1=rotate(e,6)^rotate(e,11)^rotate(e,25); let ch=(e&f)^((~e)&g); let t1=hh&+s1&+ch&+constants[i]&+w[i]; let s0=rotate(a,2)^rotate(a,13)^rotate(a,22); let maj=(a&b)^(a&c)^(b&c); let t2=s0&+maj; hh=g;g=f;f=e;e=d&+t1;d=c;c=b;b=a;a=t1&+t2 }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d
            h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }
    private static func rotate(_ value: UInt32, _ amount: UInt32) -> UInt32 { (value >> amount) | (value << (32 - amount)) }
}

private struct AgentPluginCommandResult: Sendable { var exitCode: Int32; var output: String }

private enum AgentPluginCommandRunner {
    static func run(executable: String, arguments: [String], cwd: URL, environment: [String: String], timeoutSeconds: Int) async throws -> AgentPluginCommandResult {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = cwd
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let outputTask = Task.detached {
                pipe.fileHandleForReading.readDataToEndOfFile()
            }
            let deadline = Date().addingTimeInterval(TimeInterval(max(1, timeoutSeconds)))
            while process.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            if process.isRunning { process.terminate(); throw AgentPluginManagerError.commandFailed("Command timed out") }
            let outputData = await outputTask.value
            let output = String(decoding: outputData.prefix(32_768), as: UTF8.self)
            return AgentPluginCommandResult(exitCode: process.terminationStatus, output: output)
        }.value
    }
}
