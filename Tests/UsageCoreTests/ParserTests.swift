import Foundation
import Testing
@testable import UsageCore

/// Gerçek bir Claude Code oturumundan alınmış (içerik/yol temizlenmiş) fixture.
/// Beklenen değerler fixture'dan bağımsız bir Python betiğiyle hesaplandı.
enum Fixture {
    static var realSession: URL {
        Bundle.module.url(forResource: "real_session", withExtension: "jsonl", subdirectory: "Fixtures")!
    }

    static func lines(_ url: URL) -> [Data] {
        let data = try! Data(contentsOf: url)
        return data.split(separator: 0x0A).map { Data($0) }
    }

    static func parseAll(_ url: URL) -> [LogParser.Item] {
        let parser = LogParser()
        var last: Date?
        var items: [LogParser.Item] = []
        for line in lines(url) {
            if case .item(let item) = parser.parse(line: line, fallbackTimestamp: last) {
                if case .usage(let e) = item { last = e.timestamp }
                items.append(item)
            }
        }
        return items
    }
}

@Suite struct ParserTests {
    @Test func parsesAssistantUsageFromRealSchema() throws {
        let line = Data(#"""
        {"parentUuid":"a","isSidechain":false,"message":{"model":"claude-opus-5-5","id":"msg_1","type":"message","role":"assistant","content":[{"type":"thinking"}],"usage":{"input_tokens":2,"cache_creation_input_tokens":12317,"cache_read_input_tokens":23306,"output_tokens":249,"output_tokens_details":{"thinking_tokens":25},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":12317,"ephemeral_5m_input_tokens":0},"speed":"standard"}},"requestId":"req_1","type":"assistant","uuid":"u1","timestamp":"2026-10-08T09:30:08.271Z","sessionId":"s1"}
        """#.utf8)
        let outcome = LogParser().parse(line: line, fallbackTimestamp: nil)
        guard case .item(.usage(let e)) = outcome else { Issue.record("beklenen usage, gelen \(outcome)"); return }
        #expect(e.key == "msg_1:req_1")
        #expect(e.model == "claude-opus-5-5")
        #expect(e.sessionId == "s1")
        #expect(e.inputTokens == 2)
        #expect(e.outputTokens == 249)
        #expect(e.cacheWrite5mTokens == 0)
        #expect(e.cacheWrite1hTokens == 12317)
        #expect(e.cacheReadTokens == 23306)
        #expect(e.isFast == false)
        #expect(e.timestamp == Date(timeIntervalSince1970: 1_791_451_808.271))
    }

    @Test func legacyUsageWithoutTTLBreakdownCountsAs5m() {
        let line = Data(#"{"type":"assistant","timestamp":"2025-06-01T10:00:00Z","requestId":"r","message":{"id":"m","model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":100,"cache_read_input_tokens":0}}}"#.utf8)
        guard case .item(.usage(let e)) = LogParser().parse(line: line, fallbackTimestamp: nil) else {
            Issue.record("usage bekleniyordu"); return
        }
        #expect(e.cacheWrite5mTokens == 100)
        #expect(e.cacheWrite1hTokens == 0)
    }

    @Test func skipsSyntheticAndIrrelevantAndMalformedLines() {
        let p = LogParser()
        let synthetic = Data(#"{"type":"assistant","timestamp":"2026-10-08T09:30:08Z","message":{"id":"x","model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0}}}"#.utf8)
        let user = Data(#"{"type":"user","message":{"content":"the word \"usage\" appears"}}"#.utf8)
        let mode = Data(#"{"type":"mode","sessionId":"s"}"#.utf8)
        let broken = Data(#"{"type":"assistant","message":{"usage":"#.utf8)
        #expect(p.parse(line: synthetic, fallbackTimestamp: nil) == .skipped)
        #expect(p.parse(line: user, fallbackTimestamp: nil) == .skipped)
        #expect(p.parse(line: mode, fallbackTimestamp: nil) == .skipped)
        #expect(p.parse(line: broken, fallbackTimestamp: nil) == .malformed)
    }

    @Test func costStateUsesFallbackTimestamp() {
        let line = Data(#"{"type":"cost-state","sessionId":"s1","totalCostUSD":0.7,"modelUsage":{"claude-haiku-5-5":{"inputTokens":1185,"outputTokens":164,"thinkingTokens":140,"cacheReadInputTokens":0,"cacheCreationInputTokens":0,"webSearchRequests":0,"costUSD":0.0002005}}}"#.utf8)
        let ts = Date(timeIntervalSince1970: 1_000)
        guard case .item(.costState(let cs)) = LogParser().parse(line: line, fallbackTimestamp: ts) else {
            Issue.record("cost-state bekleniyordu"); return
        }
        #expect(cs.timestamp == ts)
        #expect(cs.modelUsage["claude-haiku-5-5"]?.inputTokens == 1185)
        #expect(cs.modelUsage["claude-haiku-5-5"]?.costUSD == 0.0002005)
    }

    @Test func realSessionDedupesStreamedContentBlocks() {
        let items = Fixture.parseAll(Fixture.realSession)
        let usages = items.compactMap { if case .usage(let e) = $0 { return e } else { return nil } }
        #expect(usages.count == 30) // her content bloğu ayrı satır

        var store = UsageStore()
        store.ingest(items)
        #expect(store.entries.count == 17) // tekil message.id:requestId

        let e = Array(store.entries.values)
        #expect(e.reduce(0) { $0 + $1.inputTokens } == 38)
        #expect(e.reduce(0) { $0 + $1.outputTokens } == 6750)
        #expect(e.reduce(0) { $0 + $1.cacheWrite5mTokens } == 0)
        #expect(e.reduce(0) { $0 + $1.cacheWrite1hTokens } == 38201)
        #expect(e.reduce(0) { $0 + $1.cacheReadTokens } == 838670)
    }

    @Test func ingestingSameItemsTwiceIsIdempotent() {
        let items = Fixture.parseAll(Fixture.realSession)
        var store = UsageStore()
        store.ingest(items)
        #expect(store.ingest(items) == 0)
        #expect(store.entries.count == 17)
    }
}
