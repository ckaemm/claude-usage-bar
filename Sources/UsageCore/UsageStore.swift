import Foundation

/// Tekilleştirilmiş kullanım kayıtları + oturum başına son `cost-state`.
public struct UsageStore: Codable, Sendable {
    public private(set) var entries: [String: UsageEntry] = [:]
    public private(set) var costStates: [String: SessionCostState] = [:]

    public init() {}

    /// - Returns: yeni eklenen (daha önce görülmemiş) kayıt sayısı.
    @discardableResult
    public mutating func ingest(_ items: [LogParser.Item]) -> Int {
        var added = 0
        for item in items {
            switch item {
            case .usage(let e):
                if entries[e.key] == nil {
                    entries[e.key] = e
                    added += 1
                }
            case .costState(let cs):
                // Kümülatif: en son (veya aynı anda en büyük) durum geçerlidir.
                if let old = costStates[cs.sessionId], old == cs || old.timestamp > cs.timestamp { continue }
                costStates[cs.sessionId] = cs
                added += 1
            }
        }
        return added
    }

    /// Assistant satırlarında hiç görünmeyen modeller için `cost-state`ten türetilen ek kayıtlar
    /// (ör. Claude Code'un iç Haiku çağrıları). Zamanı oturumun son etkinliğidir → yaklaşık.
    public var supplementalEntries: [UsageEntry] {
        var modelsBySession: [String: Set<String>] = [:]
        for e in entries.values {
            if let sid = e.sessionId { modelsBySession[sid, default: []].insert(e.model) }
        }
        var out: [UsageEntry] = []
        for (sid, cs) in costStates {
            let seen = modelsBySession[sid] ?? []
            for (model, u) in cs.modelUsage where !seen.contains(model) {
                out.append(UsageEntry(
                    key: "cost-state:\(sid):\(model)", timestamp: cs.timestamp, model: model,
                    sessionId: sid, inputTokens: u.inputTokens, outputTokens: u.outputTokens,
                    cacheWrite5mTokens: u.cacheCreationInputTokens, cacheWrite1hTokens: 0,
                    cacheReadTokens: u.cacheReadInputTokens, costOverrideUSD: u.costUSD))
            }
        }
        return out
    }

    public var allEntries: [UsageEntry] { Array(entries.values) + supplementalEntries }
}
