import Foundation
import Testing
import Protocols
@testable import sloppy

private func normalizer(for tool: any CoreTool) throws -> ToolArgumentNormalizer {
    ToolArgumentNormalizer(schemaJSON: try JSONEncoder().encode(tool.parameters))
}

@Test
func normalizerReadsPropertiesFromRealToolSchemas() throws {
    let read = try normalizer(for: FilesReadTool())
    #expect(read.properties["path"] != nil)
    #expect(read.properties["offset"]?.type == "integer" || read.properties["offset"]?.type == "number")

    let lsp = try normalizer(for: LSPTool())
    #expect(lsp.properties["line"]?.type == "integer" || lsp.properties["line"]?.type == "number")
    #expect(lsp.properties["operation"]?.type == "string")
}

@Test
func normalizerDropsBooleanInOptionalNumericSlot() throws {
    let read = try normalizer(for: FilesReadTool())

    let result = read.normalize(["path": .string("a.js"), "offset": .bool(false), "maxBytes": .number(12000)])

    #expect(result.arguments["offset"] == nil)
    #expect(result.arguments["maxBytes"] == .number(12000))
    #expect(result.arguments["path"] == .string("a.js"))
    #expect(result.repairs.map(\.field) == ["offset"])
}

@Test
func normalizerConvertsNumericStringsAndRenamesCaseVariants() throws {
    let lsp = try normalizer(for: LSPTool())

    let result = lsp.normalize([
        "operation": .string("hover"), "file_path": .string("x.swift"),
        "line": .string("12"), "Character": .number(3),
    ])

    #expect(result.arguments["filePath"] == .string("x.swift"))
    #expect(result.arguments["file_path"] == nil)
    #expect(result.arguments["line"] == .number(12))
    #expect(result.arguments["character"] == .number(3))
    #expect(Set(result.repairs.map(\.field)) == ["file_path", "line", "Character"])
}

@Test
func normalizerLeavesAmbiguousOrValidArgumentsUntouched() throws {
    let lsp = try normalizer(for: LSPTool())
    let valid: [String: JSONValue] = ["operation": .string("hover"), "filePath": .string("x"), "line": .number(1)]

    #expect(lsp.normalize(valid).repairs.isEmpty)
    #expect(lsp.normalize(valid).arguments == valid)
    // Non-integral text for an integer field is not guessed.
    #expect(lsp.normalize(["line": .string("1.5")]).arguments["line"] == .string("1.5"))
    // Unknown keys are preserved, not dropped.
    #expect(lsp.normalize(["bogus": .string("v")]).arguments["bogus"] == .string("v"))
}

@Test
func normalizerFixesBooleanStringsArraysAndEnumCasing() {
    let schema = """
    {"type":"object","properties":{
      "all":{"type":"boolean"},
      "tags":{"type":"array","items":{"type":"string"}},
      "mode":{"type":"string","enum":["read_only","read_write"]},
      "id":{"type":"string"}
    },"required":["mode"]}
    """
    let n = ToolArgumentNormalizer(schemaJSON: Data(schema.utf8))

    let result = n.normalize(["all": .string("TRUE"), "tags": .string("a"), "mode": .string("Read-Only"), "id": .number(123)])

    #expect(result.arguments["all"] == .bool(true))
    #expect(result.arguments["tags"] == .array([.string("a")]))
    #expect(result.arguments["mode"] == .string("read_only"))
    // Identifiers are never coerced from numbers: tools reject them instead of addressing a different record.
    #expect(result.arguments["id"] == .number(123))
    // A required numeric/array slot is never silently dropped.
    let requiredNumber = ToolArgumentNormalizer(schemaJSON: Data(#"{"type":"object","properties":{"n":{"type":"integer"}},"required":["n"]}"#.utf8))
    #expect(requiredNumber.normalize(["n": .bool(false)]).arguments["n"] == .bool(false))
}
