import Foundation
import UserNotifications

/// Eşik uyarıları. Her pencere için en fazla bir bildirim gönderir.
@MainActor
final class Notifier {
    private let lastKeyDefaultsKey = "lastAlertWindowKey"

    /// `.app` paketi dışında (ör. `swift run`) UNUserNotificationCenter kullanılamaz.
    private var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") }

    func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// - Parameters:
    ///   - windowKey: pencereyi tekil tanımlayan anahtar (ör. sıfırlanma zamanı).
    ///   - isEstimate: yüzde yerel tahminse metinde belirtilir.
    func check(percent: Double, threshold: Double, windowKey: String, isEstimate: Bool) {
        guard available, percent >= threshold else { return }
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: lastKeyDefaultsKey) != windowKey else { return }
        defaults.set(windowKey, forKey: lastKeyDefaultsKey)

        let content = UNMutableNotificationContent()
        content.title = "Claude kullanımı %\(Int(percent.rounded()))"
        content.body = isEstimate
            ? "Tahmini 5 saatlik pencere kullanımı %\(Int(threshold)) eşiğini geçti (geçmiş en yüksek bloğa göre)."
            : "5 saatlik oturum limitinin %\(Int(threshold)) eşiği geçildi (resmi olmayan veri)."
        content.sound = .default
        let req = UNNotificationRequest(identifier: "threshold-\(windowKey)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
