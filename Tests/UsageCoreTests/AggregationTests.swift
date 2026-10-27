import Foundation
import Testing
@testable import UsageCore

@Suite struct AggregationTests {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        c.firstWeekday = 2
        return c
    }()

    private func date(_ s: String) -> Date { LogParser().parseDate(s)! }

    private func entry(_ id: String, _ ts: String, model: String = "claude-opus-5-5",
                       output: Int = 1000, session: String = "s") -> UsageEntry {
        UsageEntry(key: id, timestamp: date(ts), model: model, sessionId: session,
                   inputTokens: 0, outputTokens: output, cacheWrite5mTokens: 0,
                   cacheWrite1hTokens: 0, cacheReadTokens: 0)
    }

    private func store(_ entries: [UsageEntry], costStates: [SessionCostState] = []) -> UsageStore {
        var s = UsageStore()
        s.ingest(entries.map { .usage($0) } + costStates.map { .costState($0) })
        return s
    }

    @Test func periodsAndSevenDayBuckets() {
        // Şimdi: Çarşamba 28 Ekim 2026, 12:00 İstanbul (UTC+3)
        let now = date("2026-10-28T09:00:00Z")
        let s = store([
            entry("today", "2026-10-28T06:00:00Z"),              // bugün
            entry("monday", "2026-10-26T08:00:00Z"),             // bu hafta (Pazartesi)
            entry("sunday", "2026-10-25T20:00:00Z"),             // geçen hafta, bu ay; 7 gün içinde
            entry("lastMonth", "2026-09-30T12:00:00Z"),          // geçen ay
            entry("future", "2026-10-29T12:00:00Z"),             // gelecek → yok sayılır
            entry("sonnet", "2026-10-28T07:00:00Z", model: "claude-sonnet-5-5"),
        ])
        let snap = Aggregator.snapshot(store: s, pricing: .default, now: now, calendar: cal)
        #expect(snap.summary(.today).totals.messageCount == 2)
        #expect(snap.summary(.week).totals.messageCount == 3)
        #expect(snap.summary(.month).totals.messageCount == 4)
        #expect(snap.summary(.today).byFamily[.sonnet]?.outputTokens == 1000)
        #expect(abs(snap.summary(.today).totals.costUSD - (0.02 + 0.01)) < 1e-12)

        #expect(snap.last7Days.count == 7)
        #expect(snap.last7Days.last?.totals.messageCount == 2)
        #expect(snap.last7Days[4].totals.messageCount == 1) // 26 Ekim
        #expect(snap.last7Days[3].totals.messageCount == 1) // 25 Ekim (İstanbul saatiyle 23:00)
        #expect(snap.last7Days.reduce(0) { $0 + $1.totals.messageCount } == 4)
    }

    @Test func costStateSupplementsOnlyUnseenModels() {
        let cs = SessionCostState(sessionId: "s", timestamp: date("2026-10-28T08:00:00Z"), modelUsage: [
            "claude-opus-5-5": .init(inputTokens: 1, outputTokens: 1000, cacheReadInputTokens: 0,
                                     cacheCreationInputTokens: 0, costUSD: 0.02),
            "claude-haiku-5-5": .init(inputTokens: 1185, outputTokens: 164, cacheReadInputTokens: 0,
                                      cacheCreationInputTokens: 0, costUSD: 0.0002005),
        ])
        let s = store([entry("a", "2026-10-28T07:00:00Z")], costStates: [cs])
        #expect(s.supplementalEntries.count == 1)
        #expect(s.supplementalEntries.first?.model == "claude-haiku-5-5")

        let snap = Aggregator.snapshot(store: s, pricing: .default, now: date("2026-10-28T09:00:00Z"), calendar: cal)
        #expect(snap.hasSupplementalData)
        #expect(snap.summary(.today).byFamily[.haiku]?.costUSD == 0.0002005)
        #expect(snap.entryCount == 1)
    }

    @Test func realFixtureSupplementsHaiku() {
        var s = UsageStore()
        s.ingest(Fixture.parseAll(Fixture.realSession))
        // Fixture'daki cost-state hem opus hem haiku içerir; haiku assistant satırlarında yok.
        #expect(s.supplementalEntries.map(\.model) == ["claude-haiku-5-5"])
        #expect(s.supplementalEntries.first?.inputTokens == 1185)
    }

    @Test func latestCostStateWins() {
        let older = SessionCostState(sessionId: "s", timestamp: date("2026-10-28T08:00:00Z"), modelUsage: [
            "claude-haiku-5-5": .init(inputTokens: 1, outputTokens: 1, cacheReadInputTokens: 0, cacheCreationInputTokens: 0, costUSD: 0.1)])
        let newer = SessionCostState(sessionId: "s", timestamp: date("2026-10-28T09:00:00Z"), modelUsage: [
            "claude-haiku-5-5": .init(inputTokens: 2, outputTokens: 2, cacheReadInputTokens: 0, cacheCreationInputTokens: 0, costUSD: 0.2)])
        var s = UsageStore()
        s.ingest([.costState(newer), .costState(older)])
        #expect(s.costStates["s"]?.modelUsage["claude-haiku-5-5"]?.costUSD == 0.2)
    }
}

@Suite struct SessionBlockTests {
    private func date(_ s: String) -> Date { LogParser().parseDate(s)! }

    private func entry(_ id: String, _ ts: String, output: Int = 1000) -> UsageEntry {
        UsageEntry(key: id, timestamp: date(ts), model: "claude-opus-5-5", sessionId: "s",
                   inputTokens: 0, outputTokens: output, cacheWrite5mTokens: 0,
                   cacheWrite1hTokens: 0, cacheReadTokens: 0)
    }

    @Test func blocksStartOnHourAndSplitAfterFiveHoursOrGap() {
        let blocks = SessionBlocks.compute(entries: [
            entry("a", "2026-10-28T01:17:00Z"),
            entry("b", "2026-10-28T05:59:00Z"),  // aynı blok (01:00–06:00)
            entry("c", "2026-10-28T06:01:00Z"),  // blok süresi doldu → yeni blok 06:00
            entry("d", "2026-10-28T12:30:00Z"),  // yeni blok 12:00
        ], pricing: .default)
        #expect(blocks.map(\.start) == [date("2026-10-28T01:00:00Z"), date("2026-10-28T06:00:00Z"), date("2026-10-28T12:00:00Z")])
        #expect(blocks[0].totals.messageCount == 2)
        #expect(blocks[0].end == date("2026-10-28T06:00:00Z"))
    }

    @Test func currentBlockAndPeakFraction() throws {
        let blocks = SessionBlocks.compute(entries: [
            entry("old", "2026-10-27T01:00:00Z", output: 4000),
            entry("now", "2026-10-28T10:10:00Z", output: 1000),
        ], pricing: .default)
        let cur = try #require(SessionBlocks.current(blocks, now: date("2026-10-28T11:00:00Z")))
        #expect(cur.start == date("2026-10-28T10:00:00Z"))
        #expect(cur.fractionOfPeakBlock == 0.25)
        #expect(SessionBlocks.current(blocks, now: date("2026-10-28T15:00:01Z")) == nil)
    }
}
