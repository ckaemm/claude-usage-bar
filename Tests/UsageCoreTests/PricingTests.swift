import Foundation
import Testing
@testable import UsageCore

@Suite struct PricingTests {
    let table = PricingTable.default

    private func entry(_ model: String, input: Int = 0, output: Int = 0, w5: Int = 0, w1: Int = 0,
                       read: Int = 0, fast: Bool = false) -> UsageEntry {
        UsageEntry(key: UUID().uuidString, timestamp: Date(), model: model, sessionId: nil,
                   inputTokens: input, outputTokens: output, cacheWrite5mTokens: w5,
                   cacheWrite1hTokens: w1, cacheReadTokens: read, isFast: fast)
    }

    @Test func matchesClaudeCodeOwnCostForRealSession() throws {
        // Fixture'daki cost-state, Claude Code'un hesapladığı maliyeti içerir:
        // claude-opus-5-5 → costUSD 0.7061914 (40 in, 9505 out, 41987 1h write, 900177 read).
        let e = entry("claude-opus-5-5", input: 40, output: 9505, w1: 41987, read: 900177)
        let cost = try #require(table.cost(of: e))
        #expect(abs(cost - 0.7061914) < 1e-9)
    }

    @Test func fixtureEntriesCost() throws {
        var store = UsageStore()
        store.ingest(Fixture.parseAll(Fixture.realSession))
        let total = store.entries.values.compactMap { table.cost(of: $0) }.reduce(0, +)
        // 38×4 + 6750×20 + 38201×8 + 838670×0.2 = 608 494 → $0.608494
        #expect(abs(total - 0.608494) < 1e-9)
    }

    @Test func fallbackLookups() {
        #expect(table.price(for: "claude-opus-5-5")?.input == 4)
        #expect(table.price(for: "claude-sonnet-4-6-20260101")?.input == 3) // önek eşleşmesi
        #expect(table.price(for: "claude-haiku-9")?.input == 0.1)           // aile varsayılanı
        #expect(table.price(for: "gpt-x") == nil)
    }

    @Test func fastModeMultiplier() throws {
        let normal = try #require(table.cost(of: entry("claude-opus-5-5", output: 1_000_000)))
        let fast = try #require(table.cost(of: entry("claude-opus-5-5", output: 1_000_000, fast: true)))
        #expect(normal == 20)
        #expect(fast == 40)
    }

    @Test func costOverrideWins() {
        var e = entry("claude-haiku-5-5", input: 1185, output: 164)
        e.costOverrideUSD = 0.0002005
        #expect(table.cost(of: e) == 0.0002005)
    }

    @Test func userEditedJSONLoads() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pricing-\(UUID()).json")
        try Data(#"{"models":{"m":{"input":1,"output":2,"cacheWrite5m":3,"cacheWrite1h":4,"cacheRead":5}}}"#.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let t = try PricingTable.load(from: url)
        #expect(t.price(for: "m")?.cacheRead == 5)
        #expect(t.familyFallback == nil)
    }
}
