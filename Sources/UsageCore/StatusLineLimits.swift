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

/// Status line script'inin yazdığı `rate_limits` (`~/.claude-usage-bar/limits/<session_id>.json`).
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

    /// Klasördeki tüm oturum dosyalarını okuyup birleştirir.
    public static func loadDirectory(_ dir: URL) -> StatusLineLimits? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        return merge(files.filter { $0.pathExtension == "json" }.compactMap(load(from:)))
    }

    /// Birden çok oturumun verisini birleştirir. Her Claude Code oturumu yalnızca kendi son API
    /// yanıtındaki değeri bilir; boşta kalan bir oturumun değeri eskidir. Kurallar:
    /// - Daha geç `resets_at` daha yeni penceredir ve tercih edilir.
    /// - Aynı pencerede kullanım yalnızca artabilir; en yüksek yüzde en güncel olandır.
    public static func merge(_ all: [StatusLineLimits]) -> StatusLineLimits? {
        guard let first = all.first else { return nil }
        return all.dropFirst().reduce(first) { acc, l in
            StatusLineLimits(
                fiveHour: mergeWindow(acc.fiveHour, l.fiveHour),
                sevenDay: mergeWindow(acc.sevenDay, l.sevenDay),
                capturedAt: max(acc.capturedAt, l.capturedAt))
        }
    }

    /// `resets_at` değerleri bu kadar yakınsa aynı pencere sayılır.
    static let sameWindowTolerance: TimeInterval = 120

    static func mergeWindow(_ a: RateLimitWindow?, _ b: RateLimitWindow?) -> RateLimitWindow? {
        guard let a else { return b }
        guard let b else { return a }
        if let ra = a.resetsAt, let rb = b.resetsAt, abs(ra.timeIntervalSince(rb)) >= sameWindowTolerance {
            return ra > rb ? a : b
        }
        return a.usedPercentage >= b.usedPercentage ? a : b
    }

    /// Belirtilen süreden eski oturum dosyalarını siler (kapanmış oturumlar birikmesin).
    public static func pruneDirectory(_ dir: URL, olderThan age: TimeInterval, now: Date = Date()) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: []) else { return }
        for url in files {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let mtime, now.timeIntervalSince(mtime) > age { try? fm.removeItem(at: url) }
        }
    }

    public static func load(from url: URL) -> StatusLineLimits? {
        guard let data = try? Data(contentsOf: url),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let mtime = attrs[.modificationDate] as? Date else { return nil }
        return parse(data, capturedAt: mtime)
    }
}
