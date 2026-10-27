import Foundation

// Resmi olmayan plan limiti uç noktasının (`/api/oauth/usage`) yanıt modeli.

/// Plan limiti penceresi (ör. 5 saatlik oturum, haftalık limit).
public struct PlanLimitWindow: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var utilization: Double // 0…100
    public var resetsAt: Date?
}

public struct PlanLimits: Equatable, Sendable {
    public var windows: [PlanLimitWindow]
    public var fetchedAt: Date

    public var fiveHour: PlanLimitWindow? { windows.first { $0.id == "five_hour" } }

    /// Esnek ayrıştırma: üst düzeyde `utilization` içeren her nesne bir pencere kabul edilir.
    /// Tanınmayan biçimde nil döner.
    public static func parse(_ data: Data, now: Date = Date()) -> PlanLimits? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()

        var windows: [PlanLimitWindow] = []
        for (key, value) in obj {
            guard let dict = value as? [String: Any],
                  let util = (dict["utilization"] as? NSNumber)?.doubleValue else { continue }
            let resets = (dict["resets_at"] as? String).flatMap { iso.date(from: $0) ?? isoPlain.date(from: $0) }
            windows.append(PlanLimitWindow(id: key, title: title(for: key), utilization: util, resetsAt: resets))
        }
        guard !windows.isEmpty else { return nil }
        windows.sort { order(of: $0.id) < order(of: $1.id) }
        return PlanLimits(windows: windows, fetchedAt: now)
    }

    private static func title(for key: String) -> String {
        switch key {
        case "five_hour": return "5 saatlik oturum"
        case "seven_day": return "Haftalık (tüm modeller)"
        case "seven_day_opus": return "Haftalık (Opus)"
        case "seven_day_sonnet": return "Haftalık (Sonnet)"
        default: return key.replacingOccurrences(of: "_", with: " ")
        }
    }

    private static func order(of key: String) -> Int {
        ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"].firstIndex(of: key) ?? 99
    }
}
