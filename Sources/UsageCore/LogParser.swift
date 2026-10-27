import Foundation

/// Claude Code JSONL satırlarını ayrıştırır. Şema `~/.claude/projects/**/*.jsonl` dosyalarından doğrulandı:
/// - `type == "assistant"` satırları `message.usage` taşır; aynı yanıtın her content bloğu ayrı satırdır
///   (`apiBlockIndex` 0, 1, …) ve aynı usage'ı tekrar eder → `message.id:requestId` ile tekilleştirilir.
/// - `type == "cost-state"` satırları oturumun kümülatif model kullanımını taşır.
/// Tüm alanlar opsiyonel kabul edilir; tanınmayan veya bozuk satırlar atlanır.
public struct LogParser {
    public enum Item: Equatable {
        case usage(UsageEntry)
        case costState(SessionCostState)
    }

    public enum Outcome: Equatable {
        case item(Item)
        case skipped
        case malformed
    }

    private let decoder = JSONDecoder()
    private let isoFractional: ISO8601DateFormatter
    private let isoPlain: ISO8601DateFormatter

    public init() {
        isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
    }

    public func parseDate(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }

    /// - Parameter fallbackTimestamp: zaman damgası olmayan `cost-state` satırları için.
    public func parse(line: Data, fallbackTimestamp: Date?) -> Outcome {
        // Ucuz ön filtre: ilgilendiğimiz satırlar bu kelimelerden birini içermek zorunda.
        guard line.contains(Self.usageMarker) || line.contains(Self.costStateMarker) else { return .skipped }
        guard let raw = try? decoder.decode(RawLine.self, from: line) else { return .malformed }

        switch raw.type {
        case "assistant":
            guard let message = raw.message, let usage = message.usage,
                  let model = message.model, model != "<synthetic>",
                  let ts = raw.timestamp.flatMap(parseDate) else { return .skipped }
            let msgId = message.id ?? raw.uuid ?? UUID().uuidString
            let key = "\(msgId):\(raw.requestId ?? "")"
            let totalWrite = usage.cache_creation_input_tokens ?? 0
            var write5m = usage.cache_creation?.ephemeral_5m_input_tokens ?? 0
            let write1h = usage.cache_creation?.ephemeral_1h_input_tokens ?? 0
            if usage.cache_creation == nil { write5m = totalWrite } // eski kayıtlarda TTL ayrımı yok
            return .item(.usage(UsageEntry(
                key: key, timestamp: ts, model: model, sessionId: raw.sessionId,
                inputTokens: usage.input_tokens ?? 0,
                outputTokens: usage.output_tokens ?? 0,
                cacheWrite5mTokens: write5m,
                cacheWrite1hTokens: write1h,
                cacheReadTokens: usage.cache_read_input_tokens ?? 0,
                isFast: usage.speed == "fast"
            )))
        case "cost-state":
            guard let sid = raw.sessionId, let mu = raw.modelUsage,
                  let ts = raw.timestamp.flatMap(parseDate) ?? fallbackTimestamp else { return .skipped }
            return .item(.costState(SessionCostState(sessionId: sid, timestamp: ts, modelUsage: mu)))
        default:
            return .skipped
        }
    }

    static let usageMarker = Data("\"usage\"".utf8)
    static let costStateMarker = Data("\"cost-state\"".utf8)

    // MARK: - Ham şema (yalnızca gereken alanlar)

    private struct RawLine: Decodable {
        var type: String?
        var timestamp: String?
        var sessionId: String?
        var requestId: String?
        var uuid: String?
        var message: RawMessage?
        var modelUsage: [String: SessionCostState.ModelUsage]?
    }

    private struct RawMessage: Decodable {
        var id: String?
        var model: String?
        var usage: RawUsage?
    }

    private struct RawUsage: Decodable {
        var input_tokens: Int?
        var output_tokens: Int?
        var cache_creation_input_tokens: Int?
        var cache_read_input_tokens: Int?
        var cache_creation: RawCacheCreation?
        var speed: String?
    }

    private struct RawCacheCreation: Decodable {
        var ephemeral_5m_input_tokens: Int?
        var ephemeral_1h_input_tokens: Int?
    }
}

extension Data {
    /// Bayt dizisi araması (memmem); büyük satırlarda String'e çevirmekten çok daha ucuz.
    func contains(_ needle: Data) -> Bool {
        withUnsafeBytes { hay in
            needle.withUnsafeBytes { nd in
                guard let h = hay.baseAddress, let n = nd.baseAddress else { return false }
                return memmem(h, hay.count, n, nd.count) != nil
            }
        }
    }
}
