import Foundation

public struct Totals: Hashable, Sendable {
    public var inputTokens = 0
    public var outputTokens = 0
    public var cacheWriteTokens = 0
    public var cacheReadTokens = 0
    public var costUSD = 0.0
    /// Fiyat tablosunda karşılığı olmayan modellerin token'ları (maliyete dahil değil).
    public var unpricedTokens = 0
    public var messageCount = 0

    public init() {}

    public var totalTokens: Int { inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens }

    mutating func add(_ e: UsageEntry, cost: Double?) {
        inputTokens += e.inputTokens
        outputTokens += e.outputTokens
        cacheWriteTokens += e.cacheWriteTokens
        cacheReadTokens += e.cacheReadTokens
        if let cost { costUSD += cost } else { unpricedTokens += e.totalTokens }
        messageCount += 1
    }
}

public enum Period: String, CaseIterable, Identifiable, Sendable {
    case today = "Bugün"
    case week = "Bu hafta"
    case month = "Bu ay"
    public var id: String { rawValue }
}

public struct PeriodSummary: Sendable {
    public var period: Period
    public var totals = Totals()
    public var byFamily: [ModelFamily: Totals] = [:]
}

public struct DayBucket: Identifiable, Sendable {
    public var date: Date
    public var totals = Totals()
    public var byFamily: [ModelFamily: Totals] = [:]
    public var id: Date { date }
}

public struct UsageSnapshot: Sendable {
    public var generatedAt: Date
    public var periods: [Period: PeriodSummary]
    public var last7Days: [DayBucket]
    public var entryCount: Int
    public var malformedLines: Int
    public var hasSupplementalData: Bool

    public static let empty = UsageSnapshot(
        generatedAt: .distantPast, periods: [:], last7Days: [],
        entryCount: 0, malformedLines: 0, hasSupplementalData: false)

    public func summary(_ p: Period) -> PeriodSummary { periods[p] ?? PeriodSummary(period: p) }
}

public enum Aggregator {
    /// Haftanın Pazartesi başladığı yerel takvim.
    public static var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    public static func snapshot(store: UsageStore, pricing: PricingTable, now: Date,
                                calendar cal: Calendar = calendar, malformedLines: Int = 0) -> UsageSnapshot {
        let supplements = store.supplementalEntries
        let all = Array(store.entries.values) + supplements

        let todayStart = cal.startOfDay(for: now)
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? todayStart
        let monthStart = cal.dateInterval(of: .month, for: now)?.start ?? todayStart
        let starts: [Period: Date] = [.today: todayStart, .week: weekStart, .month: monthStart]

        var periods: [Period: PeriodSummary] = [:]
        for p in Period.allCases { periods[p] = PeriodSummary(period: p) }

        let day0 = cal.date(byAdding: .day, value: -6, to: todayStart)!
        var days: [DayBucket] = (0..<7).map { DayBucket(date: cal.date(byAdding: .day, value: $0, to: day0)!) }

        for e in all where e.timestamp <= now {
            let cost = pricing.cost(of: e)
            for p in Period.allCases where e.timestamp >= starts[p]! {
                periods[p]!.totals.add(e, cost: cost)
                periods[p]!.byFamily[e.family, default: Totals()].add(e, cost: cost)
            }
            if e.timestamp >= day0 {
                let idx = cal.dateComponents([.day], from: day0, to: cal.startOfDay(for: e.timestamp)).day ?? -1
                if days.indices.contains(idx) {
                    days[idx].totals.add(e, cost: cost)
                    days[idx].byFamily[e.family, default: Totals()].add(e, cost: cost)
                }
            }
        }

        return UsageSnapshot(
            generatedAt: now, periods: periods, last7Days: days,
            entryCount: store.entries.count, malformedLines: malformedLines,
            hasSupplementalData: !supplements.isEmpty)
    }
}
