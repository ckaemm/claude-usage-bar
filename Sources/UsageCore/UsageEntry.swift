import Foundation

/// Tek bir API yanıtının (tekilleştirilmiş) token kullanımı.
public struct UsageEntry: Codable, Hashable, Sendable {
    /// Tekilleştirme anahtarı: `messageId:requestId` (ccusage ile aynı).
    public var key: String
    public var timestamp: Date
    public var model: String
    public var sessionId: String?
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheWrite5mTokens: Int
    public var cacheWrite1hTokens: Int
    public var cacheReadTokens: Int
    public var isFast: Bool
    /// Doluysa maliyet fiyat tablosu yerine bu değerden alınır (cost-state ek kayıtları).
    public var costOverrideUSD: Double?

    public init(key: String, timestamp: Date, model: String, sessionId: String?,
                inputTokens: Int, outputTokens: Int, cacheWrite5mTokens: Int,
                cacheWrite1hTokens: Int, cacheReadTokens: Int, isFast: Bool = false,
                costOverrideUSD: Double? = nil) {
        self.key = key
        self.timestamp = timestamp
        self.model = model
        self.sessionId = sessionId
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheWrite5mTokens = cacheWrite5mTokens
        self.cacheWrite1hTokens = cacheWrite1hTokens
        self.cacheReadTokens = cacheReadTokens
        self.isFast = isFast
        self.costOverrideUSD = costOverrideUSD
    }

    public var cacheWriteTokens: Int { cacheWrite5mTokens + cacheWrite1hTokens }

    /// ccusage ile aynı tanım: giriş + çıkış + cache yazma + cache okuma.
    public var totalTokens: Int { inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens }

    public var family: ModelFamily { ModelFamily(model: model) }
}

public enum ModelFamily: String, Codable, CaseIterable, Sendable {
    case fable = "Fable"
    case opus = "Opus"
    case sonnet = "Sonnet"
    case haiku = "Haiku"
    case other = "Diğer"

    public init(model: String) {
        let m = model.lowercased()
        if m.contains("opus") { self = .opus }
        else if m.contains("sonnet") { self = .sonnet }
        else if m.contains("haiku") { self = .haiku }
        else if m.contains("fable") || m.contains("mythos") { self = .fable }
        else { self = .other }
    }
}

/// `cost-state` satırı: oturum başına kümülatif, model bazında kullanım.
/// Assistant satırlarında görünmeyen yardımcı çağrıları (ör. Haiku) yakalamak için kullanılır.
public struct SessionCostState: Codable, Hashable, Sendable {
    public struct ModelUsage: Codable, Hashable, Sendable {
        public var inputTokens: Int
        public var outputTokens: Int
        public var cacheReadInputTokens: Int
        public var cacheCreationInputTokens: Int
        public var costUSD: Double?

        public init(inputTokens: Int, outputTokens: Int, cacheReadInputTokens: Int,
                    cacheCreationInputTokens: Int, costUSD: Double?) {
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.cacheReadInputTokens = cacheReadInputTokens
            self.cacheCreationInputTokens = cacheCreationInputTokens
            self.costUSD = costUSD
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            inputTokens = (try? c.decode(Int.self, forKey: .inputTokens)) ?? 0
            outputTokens = (try? c.decode(Int.self, forKey: .outputTokens)) ?? 0
            cacheReadInputTokens = (try? c.decode(Int.self, forKey: .cacheReadInputTokens)) ?? 0
            cacheCreationInputTokens = (try? c.decode(Int.self, forKey: .cacheCreationInputTokens)) ?? 0
            costUSD = try? c.decode(Double.self, forKey: .costUSD)
        }
    }

    public var sessionId: String
    /// cost-state satırında zaman damgası yok; aynı dosyada önceki son zaman damgası kullanılır.
    public var timestamp: Date
    public var modelUsage: [String: ModelUsage]
}
