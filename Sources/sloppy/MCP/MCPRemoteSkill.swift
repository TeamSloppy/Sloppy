import Crypto
import Foundation
import MCP
import Protocols
import Yams

struct MCPRemoteSkill: Equatable, Sendable {
    static let extensionID = "io.modelcontextprotocol/skills"

    struct File: Equatable, Sendable {
        let uri: String
        let digest: String
        let size: Int
    }

    let uri: String
    let frontmatter: [String: JSONValue]
    let files: [String: File]

    init(_ entry: JSONValue) throws {
        guard let raw = entry.asObject, let uri = raw["uri"]?.asString,
              let components = URLComponents(string: uri), components.scheme != nil,
              components.path.hasSuffix("/SKILL.md"),
              let frontmatter = raw["frontmatter"]?.asObject, let name = frontmatter["name"]?.asString,
              !name.isEmpty, frontmatter["description"]?.asString?.isEmpty == false,
              let resources = raw["resources"]?.asArray, resources.count <= 512 else {
            throw MCPRegistryError.invalidResult("MCP skill needs valid frontmatter and a file manifest.")
        }
        var files: [String: File] = [:]
        for entry in resources {
            guard let object = entry.asObject, let uri = object["uri"]?.asString,
                  URLComponents(string: uri)?.scheme != nil,
                  let digest = object["digest"]?.asString, digest.hasPrefix("sha256:"),
                  digest.count == 71, digest.dropFirst(7).allSatisfy({ "0123456789abcdef".contains($0) }),
                  let size = object["size"]?.asNumber, size >= 0, size <= Double(Int32.max), size.rounded() == size,
                  files[uri] == nil else {
                throw MCPRegistryError.invalidResult("Invalid or duplicate MCP skill file.")
            }
            files[uri] = File(uri: uri, digest: digest, size: Int(size))
        }
        guard files[uri] != nil else { throw MCPRegistryError.invalidResult("MCP skill is missing its SKILL.md entry.") }
        self.uri = uri
        self.frontmatter = frontmatter
        self.files = files
    }

    var metadata: JSONValue {
        .object(["uri": .string(uri), "name": frontmatter["name"] ?? .null,
                 "description": frontmatter["description"] ?? .null])
    }

    func verifiedFile(_ fileURI: String, contents: [Resource.Content]) throws -> Data {
        guard let expected = files[fileURI], contents.count == 1, let content = contents.first,
              content.uri == fileURI else { throw MCPRegistryError.invalidResult("MCP skill returned an unexpected resource.") }
        let data = content.text.map { Data($0.utf8) } ?? content.blob.flatMap { Data(base64Encoded: $0) }
        guard let data, data.count == expected.size else { throw MCPRegistryError.invalidResult("MCP skill file size mismatch.") }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard "sha256:" + hash == expected.digest else { throw MCPRegistryError.invalidResult("MCP skill file digest mismatch.") }
        if fileURI == uri {
            guard let text = String(data: data, encoding: .utf8) else {
                throw MCPRegistryError.invalidResult("SKILL.md is not UTF-8 text.")
            }
            let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---"), end <= 256 else {
                throw MCPRegistryError.invalidResult("Invalid SKILL.md frontmatter.")
            }
            let yaml = lines[1..<end].joined(separator: "\n")
            guard yaml.utf8.count <= 32_768, let parsed = try Yams.load(yaml: yaml) as? [String: Any],
                  JSONSerialization.isValidJSONObject(parsed),
                  let parsedJSON = try JSONDecoder().decode(JSONValue.self, from: JSONSerialization.data(withJSONObject: parsed)).asObject,
                  parsedJSON == frontmatter else {
                throw MCPRegistryError.invalidResult("SKILL.md frontmatter does not match the MCP skill manifest.")
            }
        }
        return data
    }
}

extension MCPClientRegistry {
    func remoteSkills(serverID: String, cursor: String?) async throws -> [String: JSONValue] {
        let connection = try skillConnection(serverID: serverID)
        let params: [String: JSONValue] = cursor.map { ["cursor": .string($0)] } ?? [:]
        let data = try await connection.extensionRequest("skills/list", extensionID: MCPRemoteSkill.extensionID, params: params)
        guard data["resultType"]?.asString == "complete", let entries = data["skills"]?.asArray else {
            throw MCPRegistryError.invalidResult("Invalid MCP skill catalog.")
        }
        return ["server": .string(serverID), "skills": .array(entries.compactMap { try? MCPRemoteSkill($0).metadata }),
                "nextCursor": data["nextCursor"] ?? .null]
    }

    func remoteSkill(serverID: String, uri: String) async throws -> (MCPRemoteSkill, MCPServerConnection) {
        let connection = try skillConnection(serverID: serverID)
        let data = try await connection.extensionRequest("skills/get", extensionID: MCPRemoteSkill.extensionID,
                                                         params: ["uri": .string(uri)])
        guard data["resultType"]?.asString == "complete", let entry = data["skill"] else {
            throw MCPRegistryError.invalidResult("Invalid MCP skill entry.")
        }
        let skill = try MCPRemoteSkill(entry)
        guard skill.uri == uri else { throw MCPRegistryError.invalidResult("MCP server changed the requested skill identity.") }
        return (skill, connection)
    }

    private func skillConnection(serverID: String) throws -> MCPServerConnection {
        let connection = try connection(for: serverID)
        guard connection.config.exposeResources else { throw MCPRegistryError.disabledServer(serverID) }
        return connection
    }
}
