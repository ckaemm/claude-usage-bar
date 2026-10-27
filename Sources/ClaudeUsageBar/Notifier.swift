import Foundation
import UserNotifications

/// Eşik uyarıları. Her limit penceresi (adı + sıfırlanma zamanı) için en fazla bir bildirim gönderir.
@MainActor
final class Notifier {
    private let notifiedKeysDefaultsKey = "notifiedLimitWindows"

    /// `.app` paketi dışında (ör. `swift run`) UNUserNotificationCenter kullanılamaz.
    private var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") }

    func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func check(window: String, percent: Double, threshold: Double, resetsAt: Date?) {
        guard available, percent >= threshold else { return }
        let key = "\(window)|\(resetsAt.map { Int($0.timeIntervalSince1970) } ?? 0)"
        let defaults = UserDefaults.standard
        var notified = defaults.stringArray(forKey: notifiedKeysDefaultsKey) ?? []
        guard !notified.contains(key) else { return }
        notified.append(key)
        defaults.set(Array(notified.suffix(20)), forKey: notifiedKeysDefaultsKey)

        let content = UNMutableNotificationContent()
        content.title = "Claude: \(window) limiti %\(Int(percent.rounded()))"
        var body = "%\(Int(threshold)) eşiği geçildi."
        if let resetsAt {
            body += " Sıfırlanma: \(resetsAt.formatted(date: .abbreviated, time: .shortened))."
        }
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "threshold-\(key)", content: content, trigger: nil))
    }
}
