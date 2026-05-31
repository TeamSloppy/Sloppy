//
//  RegistryTypes.swift
//  ACPRegistry
//
//  ACP Agent Registry Types
//

import Foundation

// MARK: - Registry

public struct Registry: Codable, Sendable {
    public let version: String
    public let agents: [RegistryAgent]
    public let extensions: [RegistryAgent]

    public init(version: String, agents: [RegistryAgent], extensions: [RegistryAgent] = []) {
        self.version = version
        self.agents = agents
        self.extensions = extensions
    }
}

// MARK: - Agent

public struct RegistryAgent: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let version: String
    public let description: String
    public let repository: String?
    public let authors: [String]?
    public let license: String?
    public let icon: String?
    public let distribution: Distribution

    public init(
        id: String,
        name: String,
        version: String,
        description: String,
        repository: String? = nil,
        authors: [String]? = nil,
        license: String? = nil,
        icon: String? = nil,
        distribution: Distribution
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.repository = repository
        self.authors = authors
        self.license = license
        self.icon = icon
        self.distribution = distribution
    }
}

// MARK: - Distribution

public struct Distribution: Codable, Sendable {
    public let binary: [String: BinaryTarget]?
    public let npx: PackageDistribution?
    public let uvx: PackageDistribution?

    public init(
        binary: [String: BinaryTarget]? = nil,
        npx: PackageDistribution? = nil,
        uvx: PackageDistribution? = nil
    ) {
        self.binary = binary
        self.npx = npx
        self.uvx = uvx
    }

    /// Returns the best distribution method for the current platform
    public func preferred(for platform: Platform) -> DistributionMethod? {
        // Prefer binary if available for this platform
        if let binary = binary?[platform.identifier] {
            return .binary(binary)
        }

        // Fall back to npx
        if let npx = npx {
            return .npx(npx)
        }

        // Fall back to uvx
        if let uvx = uvx {
            return .uvx(uvx)
        }

        return nil
    }
}

public enum DistributionMethod: Sendable {
    case binary(BinaryTarget)
    case npx(PackageDistribution)
    case uvx(PackageDistribution)
}

// MARK: - Binary Target

public struct BinaryTarget: Codable, Sendable {
    public let archive: String
    public let cmd: String
    public let args: [String]?
    public let env: [String: String]?

    public init(
        archive: String,
        cmd: String,
        args: [String]? = nil,
        env: [String: String]? = nil
    ) {
        self.archive = archive
        self.cmd = cmd
        self.args = args
        self.env = env
    }

    public var archiveURL: URL? {
        URL(string: archive)
    }
}

// MARK: - Package Distribution

public struct PackageDistribution: Codable, Sendable {
    public let package: String
    public let args: [String]?
    public let env: [String: String]?

    public init(
        package: String,
        args: [String]? = nil,
        env: [String: String]? = nil
    ) {
        self.package = package
        self.args = args
        self.env = env
    }
}

// MARK: - Platform

public struct Platform: Sendable, Hashable {
    public let os: OS
    public let arch: Architecture

    public enum OS: String, Sendable {
        case darwin
        case linux
        case windows
    }

    public enum Architecture: String, Sendable {
        case aarch64
        case x86_64 = "x86_64"
    }

    public var identifier: String {
        "\(os.rawValue)-\(arch.rawValue)"
    }

    public init(os: OS, arch: Architecture) {
        self.os = os
        self.arch = arch
    }

    /// Detects the current platform
    public static var current: Platform {
        #if os(macOS)
        let os = OS.darwin
        #elseif os(Linux)
        let os = OS.linux
        #elseif os(Windows)
        let os = OS.windows
        #else
        let os = OS.darwin // fallback
        #endif

        #if arch(arm64)
        let arch = Architecture.aarch64
        #elseif arch(x86_64)
        let arch = Architecture.x86_64
        #else
        let arch = Architecture.aarch64 // fallback
        #endif

        return Platform(os: os, arch: arch)
    }
}
