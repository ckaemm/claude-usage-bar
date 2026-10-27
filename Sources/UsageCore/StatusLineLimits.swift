import Foundation

/// Claude Code status line JSON'undaki tek bir limit penceresi.
/// Şema (code.claude.com/docs/en/statusline): `used_percentage` 0…100, `resets_at` Unix epoch saniyesi.
public struct RateLimitWindow: Equatable, Sendable {
    public var usedPercentage: Double
    public var resetsAt: Date?

    public init(usedPercentage: Double, resetsAt: Date?) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }

    /// `resets_at` geçtiyse yüzde artık geçerli değildir (yeni pencere başlamıştır).
    public func isExpired(at now: Date) -> Bool {
        guard let resetsAt else { return false }
        return resetsAt <= now
    }
}

/// `~/.claude-usage-bar/limits.json` içeriği: status line script'inin son yazdığı `rate_limits`.
/// `rate_limits` yalnızca claude.ai Pro/Max girişinde ve oturumun ilk API yanıtından sonra gelir;
/// pencereler birbirinden bağımsız olarak eksik olabilir.
public struct StatusLineLimits: Equatable, Sendable {
    public var fiveHour: RateLimitWindow?
    public var sevenDay: RateLimitWindow?
    /// Verinin yazıldığı an (dosyanın değişiklik zamanı).
    public var capturedAt: Date

    public init(fiveHour: RateLimitWindow?, sevenDay: RateLimitWindow?, capturedAt: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.capturedAt = capturedAt
    }

    /// Bu süreden eski veri "eski" kabul edilir; Claude Code çalışmıyorsa güncellenmez.
    public static let staleAfter: TimeInterval = 15 * 60

    public func isStale(at now: Date) -> Bool {
        now.timeIntervalSince(capturedAt) > Self.staleAfter
    }

    /// `rate_limits` yoksa veya tanınan pencere içermiyorsa nil.
    public static func parse(_ data: Data, capturedAt: Date) -> StatusLineLimits? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = root["rate_limits"] as? [String: Any] else { return nil }

        func window(_ key: String) -> RateLimitWindow? {
            guard let w = limits[key] as? [String: Any],
                  let used = (w["used_percentage"] as? NSNumber)?.doubleValue else { return nil }
            let resets = (w["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return RateLimitWindow(usedPercentage: used, resetsAt: resets)
        }

        let five = window("five_hour"), week = window("seven_day")
        guard five != nil || week != nil else { return nil }
        return StatusLineLimits(fiveHour: five, sevenDay: week, capturedAt: capturedAt)
    }

    public static func load(from url: URL) -> StatusLineLimits? {
        guard let data = try? Data(contentsOf: url),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let mtime = attrs[.modificationDate] as? Date else { return nil }
        return parse(data, capturedAt: mtime)
    }
}
