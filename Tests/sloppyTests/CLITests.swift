import Foundation
import Testing
@testable import sloppy

// MARK: - CLIStyle tests

@Test
func cliStyleColorDisabledWhenNoColor() {
    // CLIStyle.isColor is computed at init time from env; we test the helper functions
    // by checking that non-color output equals input when colors are stripped.
    let raw = "hello"
    let colored = CLIStyle.green(raw)
    // If color is enabled the output contains ANSI codes; if not it equals raw.
    // Either way it must contain the original string.
    #expect(colored.contains(raw))
}

@Test
func cliStyleBoldContainsInput() {
    #expect(CLIStyle.bold("test").contains("test"))
}

@Test
func cliStyleDimContainsInput() {
    #expect(CLIStyle.dim("info").contains("info"))
}

@Test
func cliStyleCyanBoldContainsInput() {
    #expect(CLIStyle.cyanBold("cmd").contains("cmd"))
}

@Test
func cliStyleRedBoldContainsInput() {
    #expect(CLIStyle.redBold("err").contains("err"))
}

@Test
func cliStyleWhiteBoldContainsInput() {
    #expect(CLIStyle.whiteBold("id-123").contains("id-123"))
}

// MARK: - CLIFormatters tests

@Test
func cliFormattersResolvesKnownFormats() {
    #expect(CLIFormatters.resolveFormat("json") == .json)
    #expect(CLIFormatters.resolveFormat("table") == .table)
    #expect(CLIFormatters.resolveFormat("JSON") == .json)
}

@Test
func cliFormattersResolvesUnknownAsJSON() {
    #expect(CLIFormatters.resolveFormat("xml") == .json)
    #expect(CLIFormatters.resolveFormat("") == .json)
}

@Test
func cliFormattersOutputJSONParseable() {
    let json = #"{"key":"value"}"#.data(using: .utf8)!
    // printJSON should not crash on valid JSON data
    // We just verify it does not throw
    CLIFormatters.printJSON(json)
}

@Test
func cliFormattersPrintTableEmpty() {
    // Printing an empty table should produce "(no results)"  output without crashing
    CLIFormatters.printTable(
        rows: [String](),
        columns: [(header: "ID", value: { $0 })]
    )
}

@Test
func cliFormattersPrintTableNonEmpty() {
    let rows = ["alpha", "beta", "gamma"]
    CLIFormatters.printTable(
        rows: rows,
        columns: [
            (header: "Name", value: { $0 }),
            (header: "Length", value: { "\($0.count)" }),
        ]
    )
}

// MARK: - SloppyCLIClient resolve tests

@Test
func cliClientResolveUsesDefaultURL() {
    let client = SloppyCLIClient.resolve(url: nil, token: nil, verbose: false)
    // When no env or config is set falls back to the default
    #expect(client.baseURL.hasPrefix("http"))
    #expect(!client.baseURL.hasSuffix("/"))
}

@Test
func cliClientResolveUsesExplicitURL() {
    let client = SloppyCLIClient.resolve(url: "http://example.com:9999", token: "tok", verbose: false)
    #expect(client.baseURL == "http://example.com:9999")
    #expect(client.token == "tok")
}

@Test
func cliClientResolveStripsTrailingSlash() {
    let client = SloppyCLIClient.resolve(url: "http://localhost:8080/", token: nil, verbose: false)
    #expect(!client.baseURL.hasSuffix("/"))
}

@Test
func cliClientVerboseFlagPropagates() {
    let client = SloppyCLIClient.resolve(url: nil, token: nil, verbose: true)
    #expect(client.verbose == true)
}

// MARK: - CLIClientError descriptions

@Test
func cliClientErrorNotConnectedDescription() {
    let err = CLIClientError.notConnected("http://localhost:1234")
    #expect(err.errorDescription?.contains("http://localhost:1234") == true)
}

@Test
func cliClientErrorHTTPErrorDescription() {
    let err = CLIClientError.httpError(404, "not found")
    #expect(err.errorDescription?.contains("404") == true)
}

@Test
func cliClientErrorInvalidURLDescription() {
    let err = CLIClientError.invalidURL
    #expect(err.errorDescription != nil)
}
