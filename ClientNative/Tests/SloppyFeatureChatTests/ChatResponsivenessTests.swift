import Foundation
import Testing
@testable import SloppyFeatureChat

@Suite("Chat responsiveness contracts")
struct ChatResponsivenessTests {
    @Test func exactFencedSourceAndExplicitBashOnly() throws {
        let source = "```\n/Library/Java/Home\n```\n```bash\nprintf 'ok\\n'\n```\n```swift\nprint(1)\n```"
        let blocks = ChatFencedCode.blocks(in: source)
        #expect(blocks.count == 3)
        #expect(blocks[0].code == "/Library/Java/Home\n")
        #expect(!blocks[0].isBash)
        #expect(blocks[1].isBash)
        #expect(blocks[1].code == "printf 'ok\\n'\n")
        #expect(!blocks[2].isBash)
    }
    @Test func partialFenceNeverEnablesRun() throws {
        let block = try #require(ChatFencedCode.blocks(in: "```bash\nprintf ok").first)
        #expect(!block.isComplete)
        #expect(block.code == "printf ok")
    }
    @Test func unknownLanguageAndCRLFArePreserved() throws {
        let block = try #require(ChatFencedCode.blocks(in: "~~~unknown\r\n  a\r\n\r\n~~~\r\n").first)
        #expect(block.code == "  a\r\n\r\n")
        #expect(!block.isBash)
    }
    @Test func multilineUnicodeCaretPreservesSuffix() throws {
        let prefix = "Привет 👩🏽‍💻\nпроверь @rea"
        let text = prefix + " потом"
        let query = try #require(ChatComposerQuery.parse(text, cursorOffset: prefix.count))
        let item = ChatComposerSuggestion(id: "r", kind: .file, title: "README", subtitle: "", insertion: "@README")
        #expect(query.applying(item, to: text).text == "Привет 👩🏽‍💻\nпроверь @README потом")
    }
}

@Suite("Suggestion cache contracts", .serialized)
@MainActor
struct ChatSuggestionCacheTests {
    @Test func deduplicatesAndScopesRequests() async throws {
        let cache = ChatSuggestionCache<[String]>(lifetime: 60)
        var calls = 0
        let fetch: @MainActor () async throws -> [String] = {
            calls += 1
            try await Task.sleep(for: .milliseconds(40))
            return ["command"]
        }
        async let first = cache.load("instance|project|agent", fetch: fetch)
        async let second = cache.load("instance|project|agent", fetch: fetch)
        let pair = try await (first, second)
        #expect(pair.0 == pair.1)
        #expect(calls == 1)
        _ = try await cache.load("instance|project|agent", fetch: fetch)
        #expect(calls == 1)
        _ = try await cache.load("remote|project|agent", fetch: fetch)
        #expect(calls == 2)
        print("SUGGESTION_FIXTURE requests=\(cache.requestCount) sharedFetch=\(String(describing: cache.lastFetchDuration))")
    }
    @Test func errorDoesNotBecomeEmptySuccessAndRetryWorks() async throws {
        let cache = ChatSuggestionCache<[String]>(lifetime: 60)
        do {
            _ = try await cache.load("key") { throw URLError(.notConnectedToInternet) }
            Issue.record("Expected network failure")
        } catch {}
        #expect(cache.cached("key") == nil)
        let value = try await cache.load("key") { ["recovered"] }
        #expect(value == ["recovered"])
    }
    @Test func invalidationRejectsLateFetch() async throws {
        let cache = ChatSuggestionCache<[String]>(lifetime: 60)
        let old = Task { try await cache.load("key") {
            try? await Task.sleep(for: .milliseconds(30))
            return ["stale"]
        } }
        await Task.yield()
        cache.invalidate()
        let value = try await cache.load("key") { ["fresh"] }
        _ = await old.result
        #expect(value == ["fresh"])
        #expect(cache.cached("key") == ["fresh"])
    }
}
