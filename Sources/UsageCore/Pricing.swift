import Foundation

/// 1M token başına USD fiyatlar.
public struct ModelPrice: Codable, Hashable, Sendable {
    public var input: Double
    public var output: Double
    public var cacheWrite5m: Double
    public var cacheWrite1h: Double
    public var cacheRead: Double
    /// `usage.speed == "fast"` olan istekler için çarpan (ör. Opus fast mode 2x).
    public var fastMultiplier: Double?

    public init(input: Double, output: Double, cacheWrite5m: Double, cacheWrite1h: Double,
                cacheRead: Double, fastMultiplier: Double? = nil) {
        self.input = input
        self.output = output
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.cacheRead = cacheRead
        self.fastMultiplier = fastMultiplier
    }
}

/// Kullanıcının düzenleyebileceği fiyat tablosu (`pricing.json`).
public struct PricingTable: Codable, Sendable {
    public var models: [String: ModelPrice]
    /// Tabloda bulunmayan modeller için aile → model eşlemesi (ör. "opus" → "claude-opus-5-5").
    public var familyFallback: [String: String]?

    public init(models: [String: ModelPrice], familyFallback: [String: String]? = nil) {
        self.models = models
        self.familyFallback = familyFallback
    }

    public static func load(from url: URL) throws -> PricingTable {
        try JSONDecoder().decode(PricingTable.self, from: Data(contentsOf: url))
    }

    public static let `default`: PricingTable =
        try! JSONDecoder().decode(PricingTable.self, from: Data(defaultJSON.utf8))

    /// Kesin eşleşme → en uzun önek eşleşmesi (tarih ekli kimlikler için) → aile varsayılanı.
    public func price(for model: String) -> ModelPrice? {
        if let p = models[model] { return p }
        if let key = models.keys.filter({ model.hasPrefix($0) }).max(by: { $0.count < $1.count }) {
            return models[key]
        }
        let fam = ModelFamily(model: model).rawValue.lowercased()
        if let target = familyFallback?[fam] { return models[target] }
        return nil
    }

    /// Maliyet (USD); fiyatı bilinmeyen modelde nil.
    public func cost(of e: UsageEntry) -> Double? {
        if let c = e.costOverrideUSD { return c }
        guard let p = price(for: e.model) else { return nil }
        let m = 1_000_000.0
        var c = Double(e.inputTokens) * p.input / m
            + Double(e.outputTokens) * p.output / m
            + Double(e.cacheWrite5mTokens) * p.cacheWrite5m / m
            + Double(e.cacheWrite1hTokens) * p.cacheWrite1h / m
            + Double(e.cacheReadTokens) * p.cacheRead / m
        if e.isFast { c *= p.fastMultiplier ?? 1 }
        return c
    }

    /// Varsayılan tablo: Anthropic API liste fiyatları (Ekim 2026).
    /// Cache yazma: 5 dk = 1.25× giriş, 1 sa = 2× giriş. Cache okuma modele göre değişir.
    /// Not: Haiku 5.5'in 100K üstü istem fiyatlandırması ($0.50/$2.50) modellenmemiştir.
    public static let defaultJSON = """
    {
      "_note": "USD / 1M token. Düzenleyebilirsiniz; uygulama dosya değişince yeniden yükler.",
      "models": {
        "claude-fable-5-1":  { "input": 10,   "output": 50,   "cacheWrite5m": 12.5,  "cacheWrite1h": 20,  "cacheRead": 0.25 },
        "claude-mythos-5-1": { "input": 10,   "output": 50,   "cacheWrite5m": 12.5,  "cacheWrite1h": 20,  "cacheRead": 0.25 },
        "claude-fable-5":    { "input": 10,   "output": 50,   "cacheWrite5m": 12.5,  "cacheWrite1h": 20,  "cacheRead": 1.0 },
        "claude-mythos-5":   { "input": 10,   "output": 50,   "cacheWrite5m": 12.5,  "cacheWrite1h": 20,  "cacheRead": 1.0 },
        "claude-opus-5-5":   { "input": 4,    "output": 20,   "cacheWrite5m": 5,     "cacheWrite1h": 8,   "cacheRead": 0.2,  "fastMultiplier": 2 },
        "claude-opus-5":     { "input": 5,    "output": 25,   "cacheWrite5m": 6.25,  "cacheWrite1h": 10,  "cacheRead": 0.5,  "fastMultiplier": 2 },
        "claude-opus-4-8":   { "input": 5,    "output": 25,   "cacheWrite5m": 6.25,  "cacheWrite1h": 10,  "cacheRead": 0.5 },
        "claude-opus-4-7":   { "input": 5,    "output": 25,   "cacheWrite5m": 6.25,  "cacheWrite1h": 10,  "cacheRead": 0.5 },
        "claude-opus-4-6":   { "input": 5,    "output": 25,   "cacheWrite5m": 6.25,  "cacheWrite1h": 10,  "cacheRead": 0.5 },
        "claude-sonnet-5-5": { "input": 2,    "output": 10,   "cacheWrite5m": 2.5,   "cacheWrite1h": 4,   "cacheRead": 0.2 },
        "claude-sonnet-5":   { "input": 2,    "output": 10,   "cacheWrite5m": 2.5,   "cacheWrite1h": 4,   "cacheRead": 0.2 },
        "claude-sonnet-4-6": { "input": 3,    "output": 15,   "cacheWrite5m": 3.75,  "cacheWrite1h": 6,   "cacheRead": 0.3 },
        "claude-haiku-5-5":  { "input": 0.1,  "output": 0.5,  "cacheWrite5m": 0.125, "cacheWrite1h": 0.2, "cacheRead": 0.01 },
        "claude-haiku-4-5":  { "input": 1,    "output": 5,    "cacheWrite5m": 1.25,  "cacheWrite1h": 2,   "cacheRead": 0.1 }
      },
      "familyFallback": {
        "fable": "claude-fable-5-1",
        "opus": "claude-opus-5-5",
        "sonnet": "claude-sonnet-5-5",
        "haiku": "claude-haiku-5-5"
      }
    }
    """
}
