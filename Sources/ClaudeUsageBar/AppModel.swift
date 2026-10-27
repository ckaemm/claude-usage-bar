import Combine
import Foundation
import SwiftUI
import UsageCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot = .empty
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var pricingError: String?
    /// Claude Code status line'ından gelen 5 saatlik / haftalık limitler (yoksa nil).
    @Published private(set) var limits: StatusLineLimits?
    @Published private(set) var statusLineStatus: StatusLineInstaller.Status = .notInstalled(existingCommand: nil)
    @Published var statusLineMessage: String?

    let settings = AppSettings()

    private let engine = UsageEngine(roots: UsageEngine.defaultRoots, cacheURL: AppPaths.cacheURL)
    private var watcher: FileWatcher?
    private var limitsWatcher: FileWatcher?
    let installer = StatusLineInstaller.default
    private var timer: Timer?
    private var pendingRefresh = false
    private var pricing: PricingTable = .default
    private var pricingModified: Date?
    private var cancellables: Set<AnyCancellable> = []
    private let notifier = Notifier()

    init() {
        ensurePricingFile()
        startWatching()
        startWatchingLimits()
        reloadStatusLineStatus()
        scheduleTimer()
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                // AppStorage değişiklikleri willChange ile gelir; değer bir sonraki döngüde okunur.
                DispatchQueue.main.async { self?.settingsChanged() }
            }
            .store(in: &cancellables)
        refresh()
    }

    // MARK: - Yenileme

    func refresh() {
        guard !isRefreshing else { pendingRefresh = true; return }
        isRefreshing = true
        reloadPricingIfNeeded()
        let pricing = self.pricing
        Task {
            let snap = await engine.refresh(pricing: pricing)
            self.apply(snap)
        }
    }

    /// Önbelleği silip tüm logları baştan okur.
    func rebuild() {
        guard !isRefreshing else { return }
        isRefreshing = true
        reloadPricingIfNeeded(force: true)
        let pricing = self.pricing
        Task {
            let snap = await engine.rebuild(pricing: pricing)
            self.apply(snap)
        }
    }

    private func apply(_ snap: UsageSnapshot) {
        snapshot = snap
        lastUpdated = snap.generatedAt
        isRefreshing = false
        didUpdate()
        if pendingRefresh {
            pendingRefresh = false
            refresh()
        }
    }

    private func didUpdate() {
        reloadLimits()
    }

    // MARK: - Plan limitleri (Claude Code status line → ~/.claude-usage-bar/limits/<oturum>.json)

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
        checkThreshold()
    }

    /// Geçerli (süresi dolmamış) 5 saatlik pencere.
    func fiveHour(at now: Date = Date()) -> RateLimitWindow? {
        guard let w = limits?.fiveHour, !w.isExpired(at: now) else { return nil }
        return w
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

    /// Eşik uyarıları yalnızca status line verisiyle ve güncel veriyle çalışır.
    private func checkThreshold() {
        guard settings.alertEnabled, let l = limits, !l.isStale(at: Date()) else { return }
        let now = Date()
        for (name, w) in [("5 saatlik oturum", l.fiveHour), ("Haftalık", l.sevenDay)] {
            guard let w, !w.isExpired(at: now) else { continue }
            notifier.check(window: name, percent: w.usedPercentage, threshold: settings.alertThreshold,
                           resetsAt: w.resetsAt)
        }
    }

    private func startWatching() {
        let paths = UsageEngine.defaultRoots.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
        let watcher = FileWatcher(paths: paths) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        watcher.start()
        self.watcher = watcher
    }

    private var scheduledInterval: Double = 0

    private func scheduleTimer() {
        let interval = max(15, settings.refreshInterval)
        guard interval != scheduledInterval else { return }
        scheduledInterval = interval
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        t.tolerance = interval * 0.1
        RunLoop.main.add(t, forMode: .common) // popover açıkken de çalışsın
        timer = t
    }

    private func settingsChanged() {
        scheduleTimer()
        checkThreshold()
    }

    // MARK: - Fiyat tablosu

    private func ensurePricingFile() {
        let fm = FileManager.default
        try? fm.createDirectory(at: AppPaths.supportDir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: AppPaths.pricingURL.path) {
            try? Data(PricingTable.defaultJSON.utf8).write(to: AppPaths.pricingURL, options: .atomic)
        }
    }

    private func reloadPricingIfNeeded(force: Bool = false) {
        let url = AppPaths.pricingURL
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard force || mtime != pricingModified else { return }
        pricingModified = mtime
        do {
            pricing = try PricingTable.load(from: url)
            pricingError = nil
        } catch {
            pricing = .default
            pricingError = "pricing.json okunamadı; varsayılan fiyatlar kullanılıyor."
        }
    }

    // MARK: - Menü çubuğu metni

    func menuBarText(mode: MenuBarMode) -> String {
        switch mode {
        case .iconOnly:
            return ""
        case .tokens:
            return Format.tokens(snapshot.summary(.today).totals.totalTokens)
        case .cost:
            return Format.cost(snapshot.summary(.today).totals.costUSD)
        case .percent:
            guard let w = fiveHour() else { return "—" }
            return "\(Int(w.usedPercentage.rounded()))%"
        }
    }

    func openPricingFile() {
        ensurePricingFile()
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.pricingURL])
    }
}

enum Format {
    static func tokens(_ n: Int) -> String {
        let d = Double(n)
        switch n {
        case ..<1_000: return "\(n)"
        case ..<1_000_000: return String(format: d < 10_000 ? "%.1fK" : "%.0fK", d / 1_000)
        case ..<1_000_000_000: return String(format: d < 10_000_000 ? "%.2fM" : "%.1fM", d / 1_000_000)
        default: return String(format: "%.2fB", d / 1_000_000_000)
        }
    }

    static func cost(_ c: Double) -> String {
        if c > 0 && c < 0.01 { return "<$0.01" }
        return c < 10 ? String(format: "$%.2f", c) : String(format: "$%.0f", c)
    }

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
