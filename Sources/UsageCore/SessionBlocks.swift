import Foundation

/// Yerel 5 saatlik pencere tahmini (ccusage "billing block" mantığı):
/// blok ilk mesajın saatine yuvarlanarak başlar ve 5 saat sürer; blok bittiğinde
/// veya 5 saatten uzun boşluk olduğunda yeni blok başlar. Sunucudaki gerçek pencereyle birebir olmayabilir.
public struct SessionBlock: Hashable, Sendable {
    public static let duration: TimeInterval = 5 * 3600

    public var start: Date
    public var lastActivity: Date
    public var totals = Totals()
    /// Bu bloğun maliyetinin geçmişteki en yüksek tamamlanmış bloğa oranı (0…∞); geçmiş yoksa nil.
    public var fractionOfPeakBlock: Double?

    public var end: Date { start.addingTimeInterval(Self.duration) }

    public func isActive(at now: Date) -> Bool {
        now < end && now.timeIntervalSince(lastActivity) < Self.duration
    }
}

public enum SessionBlocks {
    public static func compute(entries: [UsageEntry], pricing: PricingTable) -> [SessionBlock] {
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        var blocks: [SessionBlock] = []
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        for e in sorted {
            if var b = blocks.last,
               e.timestamp < b.end,
               e.timestamp.timeIntervalSince(b.lastActivity) < SessionBlock.duration {
                b.lastActivity = e.timestamp
                b.totals.add(e, cost: pricing.cost(of: e))
                blocks[blocks.count - 1] = b
            } else {
                let hour = utc.dateInterval(of: .hour, for: e.timestamp)?.start ?? e.timestamp
                var b = SessionBlock(start: hour, lastActivity: e.timestamp)
                b.totals.add(e, cost: pricing.cost(of: e))
                blocks.append(b)
            }
        }
        return blocks
    }

    /// Şu an etkin olan blok; etkin blok yoksa nil.
    public static func current(_ blocks: [SessionBlock], now: Date) -> SessionBlock? {
        guard var last = blocks.last, last.isActive(at: now) else { return nil }
        let peak = blocks.dropLast().map(\.totals.costUSD).max() ?? 0
        last.fractionOfPeakBlock = peak > 0 ? last.totals.costUSD / peak : nil
        return last
    }
}
