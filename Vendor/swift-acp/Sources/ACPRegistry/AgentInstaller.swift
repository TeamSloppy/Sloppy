//
//  AgentInstaller.swift
//  ACPRegistry
//
//  Utility for downloading and installing agents from the registry
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Agent Installer

public actor AgentInstaller {
    private let session: URLSession
    private let installDirectory: URL

    // MARK: - Initialization

    public init(
        session: URLSession = .shared,
        installDirectory: URL? = nil
    ) {
        self.session = session
        self.installDirectory = installDirectory ?? Self.defaultInstallDirectory
    }

    private static var defaultInstallDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ACPAgents", isDirectory: true)
    }

    // MARK: - Public API

    /// Installs an agent from the registry
    public func install(_ agent: RegistryAgent, platform: Platform = .current) async throws -> InstalledAgent {
        guard let method = agent.distribution.preferred(for: platform) else {
            throw RegistryError.unsupportedPlatform
        }

        switch method {
        case .binary(let target):
            return try await installBinary(agent: agent, target: target)
        case .npx(let pkg):
            return InstalledAgent(
                id: agent.id,
                name: agent.name,
                version: agent.version,
                executablePath: "npx",
                arguments: [pkg.package] + (pkg.args ?? []),
                environment: pkg.env ?? [:]
            )
        case .uvx(let pkg):
            return InstalledAgent(
                id: agent.id,
                name: agent.name,
                version: agent.version,
                executablePath: "uvx",
                arguments: [pkg.package] + (pkg.args ?? []),
                environment: pkg.env ?? [:]
            )
        }
    }

    /// Checks if an agent is already installed
    public func isInstalled(_ agent: RegistryAgent) -> Bool {
        let agentDir = installDirectory.appendingPathComponent(agent.id)
        return FileManager.default.fileExists(atPath: agentDir.path)
    }

    /// Returns the installed agent info if available
    public func installedAgent(_ agentId: String) -> InstalledAgent? {
        let metadataFile = installDirectory
            .appendingPathComponent(agentId)
            .appendingPathComponent("metadata.json")

        guard let data = try? Data(contentsOf: metadataFile),
              let installed = try? JSONDecoder().decode(InstalledAgent.self, from: data) else {
            return nil
        }

        return installed
    }

    /// Lists all installed agents
    public func installedAgents() -> [InstalledAgent] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: installDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return contents.compactMap { dir in
            let metadataFile = dir.appendingPathComponent("metadata.json")
            guard let data = try? Data(contentsOf: metadataFile),
                  let installed = try? JSONDecoder().decode(InstalledAgent.self, from: data) else {
                return nil
            }
            return installed
        }
    }

    /// Uninstalls an agent
    public func uninstall(_ agentId: String) throws {
        let agentDir = installDirectory.appendingPathComponent(agentId)
        try FileManager.default.removeItem(at: agentDir)
    }

    // MARK: - Private Methods

    enum BinaryArchiveKind: Equatable {
        case zip
        case tarGzip
        case tarBzip2
        case rawBinary
    }

    private func installBinary(agent: RegistryAgent, target: BinaryTarget) async throws -> InstalledAgent {
        guard let archiveURL = target.archiveURL else {
            throw RegistryError.downloadFailed(URLError(.badURL))
        }

        // Create agent directory
        let agentDir = installDirectory.appendingPathComponent(agent.id)
        try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)

        // Download archive
        let (tempURL, _) = try await session.download(from: archiveURL)

        // Determine executable path
        let executablePath = agentDir.appendingPathComponent(target.cmd).path

        do {
            // Extract archive or install raw binary directly.
            try await installBinaryPayload(from: tempURL, to: agentDir, executablePath: executablePath, archiveURL: archiveURL)
        } catch {
            try? FileManager.default.removeItem(at: agentDir)
            throw error
        }

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)

        // Make executable and remove quarantine
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executablePath
        )
        removeQuarantineAttribute(from: executablePath)

        let installed = InstalledAgent(
            id: agent.id,
            name: agent.name,
            version: agent.version,
            executablePath: executablePath,
            arguments: target.args ?? [],
            environment: target.env ?? [:]
        )

        // Save metadata
        let metadataFile = agentDir.appendingPathComponent("metadata.json")
        let data = try JSONEncoder().encode(installed)
        try data.write(to: metadataFile)

        return installed
    }

    private func installBinaryPayload(from source: URL, to destination: URL, executablePath: String, archiveURL: URL) async throws {
        switch Self.binaryArchiveKind(for: archiveURL) {
        case .rawBinary:
            let executableURL = URL(fileURLWithPath: executablePath)
            let executableDirectory = executableURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: executableURL.path) {
                try FileManager.default.removeItem(at: executableURL)
            }
            try FileManager.default.moveItem(at: source, to: executableURL)
        case .zip, .tarGzip, .tarBzip2:
            try await extractArchive(from: source, to: destination, archiveURL: archiveURL)
        }
    }

    private func extractArchive(from source: URL, to destination: URL, archiveURL: URL) async throws {
        let archiveKind = Self.binaryArchiveKind(for: archiveURL)

        let process = Process()
        let pipe = Pipe()
        process.standardError = pipe

        switch archiveKind {
        case .zip:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", source.path, "-d", destination.path]
        case .tarGzip:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xzf", source.path, "-C", destination.path]
        case .tarBzip2:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xjf", source.path, "-C", destination.path]
        case .rawBinary:
            throw RegistryError.extractionFailed(NSError(
                domain: "ACPRegistry",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Raw binaries should not be extracted"]
            ))
        }

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw RegistryError.extractionFailed(NSError(
                domain: "ACPRegistry",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: errorMessage]
            ))
        }
    }

    static func binaryArchiveKind(for archiveURL: URL) -> BinaryArchiveKind {
        let urlString = archiveURL.absoluteString.lowercased()

        if urlString.hasSuffix(".zip") {
            return .zip
        }

        if urlString.hasSuffix(".tar.gz") || urlString.hasSuffix(".tgz") {
            return .tarGzip
        }

        if urlString.hasSuffix(".tar.bz2") || urlString.hasSuffix(".tbz2") {
            return .tarBzip2
        }

        return .rawBinary
    }

    /// Remove macOS quarantine attribute to avoid security prompts
    private func removeQuarantineAttribute(from path: String) {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-d", "com.apple.quarantine", path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        #endif
    }
}

// MARK: - Installed Agent

public struct InstalledAgent: Codable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let executablePath: String
    public let arguments: [String]
    public let environment: [String: String]

    public init(
        id: String,
        name: String,
        version: String,
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
    }
}
