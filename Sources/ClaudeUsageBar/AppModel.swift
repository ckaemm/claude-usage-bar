import Combine
import Foundation
import SwiftUI
import UsageCore

/// Claude Code status line'ından gelen 5 saatlik ve haftalık limit yüzdelerini izler.
@MainActor
final class AppModel: ObservableObject {
    /// Tüm oturum dosyalarının birleşimi (yoksa nil).
    @Published private(set) var limits: StatusLineLimits?
    @Published private(set) var statusLineStatus: StatusLineInstaller.Status = .notInstalled(existingCommand: nil)
    @Published var statusLineMessage: String?
    /// Menü çubuğu metninin süresi dolan pencereleri ve "eski" durumunu yakalaması için.
    @Published private(set) var now = Date()

    let settings = AppSettings()
    let installer = StatusLineInstaller.default

    private var limitsWatcher: FileWatcher?
    private var timer: Timer?
    private let notifier = Notifier()
    private var cancellables: Set<AnyCancellable> = []

    init() {
        startWatchingLimits()
        reloadStatusLineStatus()
        startTimer()
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                // AppStorage değişiklikleri willChange ile gelir; değer bir sonraki döngüde okunur.
                DispatchQueue.main.async { self?.checkThreshold() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Limitler (~/.claude-usage-bar/limits/<oturum>.json)

    private func startWatchingLimits() {
        try? installer.prepareSupportDir() // rename olaylarını yakalamak için klasör izlenir
        // Haftalık pencereden eski oturum dosyalarına gerek yok.
        StatusLineLimits.pruneDirectory(installer.limitsDir, olderThan: 8 * 86400)
        let w = FileWatcher(paths: [installer.supportDir.path], latency: 0.3) { [weak self] in
            Task { @MainActor in self?.reloadLimits() }
        }
        w.start()
        limitsWatcher = w
        reloadLimits()
    }

    func reloadLimits() {
        let l = StatusLineLimits.loadDirectory(installer.limitsDir)
        if l != limits { limits = l }
        now = Date()
        checkThreshold()
    }

    /// Veri dosyaya yazıldıkça gelir; zamanlayıcı yalnızca sıfırlanma ve "eski" durumunu günceller.
    private func startTimer() {
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadLimits() }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common) // popover açıkken de çalışsın
        timer = t
    }

    /// Süresi dolmamış pencere; dolduysa nil.
    private func current(_ w: RateLimitWindow?) -> RateLimitWindow? {
        guard let w, !w.isExpired(at: now) else { return nil }
        return w
    }

    // MARK: - Menü çubuğu metni

    func menuBarText(mode: MenuBarMode) -> String {
        func pct(_ w: RateLimitWindow?) -> String {
            current(w).map { "%\(Int($0.usedPercentage.rounded()))" } ?? "—"
        }
        switch mode {
        case .iconOnly: return ""
        case .fiveHour: return pct(limits?.fiveHour)
        case .both: return "5s \(pct(limits?.fiveHour)) · 7g \(pct(limits?.sevenDay))"
        }
    }

    // MARK: - Status line kurulumu

    func reloadStatusLineStatus() {
        do {
            statusLineStatus = try installer.status()
        } catch {
            statusLineMessage = error.localizedDescription
        }
    }

    /// - Returns: mevcut bir status line varsa onay için onun komutu (kurulum yapılmaz).
    @discardableResult
    func installStatusLine(confirmedWrapping: Bool = false) -> String? {
        defer { reloadStatusLineStatus() }
        do {
            try installer.install(confirmedWrapping: confirmedWrapping)
            statusLineMessage = "Kuruldu. Claude Code'daki bir sonraki yanıtla birlikte veriler gelmeye başlar."
            return nil
        } catch StatusLineInstaller.InstallError.needsConfirmation(let cmd) {
            return cmd
        } catch {
            statusLineMessage = error.localizedDescription
            return nil
        }
    }

    func uninstallStatusLine() {
        defer { reloadStatusLineStatus(); reloadLimits() }
        do {
            try installer.uninstall()
            statusLineMessage = "Kaldırıldı."
        } catch {
            statusLineMessage = error.localizedDescription
        }
    }

    var isStatusLineInstalled: Bool {
        if case .installed = statusLineStatus { return true }
        return false
    }

    // MARK: - Bildirim

    func requestNotificationPermission() { notifier.requestAuthorization() }

    /// Eşik uyarıları yalnızca güncel veriyle çalışır.
    private func checkThreshold() {
        guard settings.alertEnabled, let l = limits, !l.isStale(at: now) else { return }
        for (name, w) in [("5 saatlik oturum", l.fiveHour), ("Haftalık", l.sevenDay)] {
            guard let w = current(w) else { continue }
            notifier.check(window: name, percent: w.usedPercentage, threshold: settings.alertThreshold,
                           resetsAt: w.resetsAt)
        }
    }
}

enum Format {
    static func countdown(to date: Date, from now: Date = Date()) -> String {
        let s = max(0, Int(date.timeIntervalSince(now)))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d) g \(h) sa" }
        return h > 0 ? "\(h) sa \(m) dk" : "\(m) dk"
    }

    static func ago(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        switch s {
        case ..<60: return "az önce"
        case ..<3600: return "\(s / 60) dk önce"
        case ..<86400: return "\(s / 3600) sa önce"
        default: return date.formatted(date: .abbreviated, time: .shortened)
        }
    }
}
