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
    @Published private(set) var planLimits: PlanLimits?
    @Published private(set) var planLimitError: String?

    let settings = AppSettings()

    private let engine = UsageEngine(roots: UsageEngine.defaultRoots, cacheURL: AppPaths.cacheURL)
    private var watcher: FileWatcher?
    private var timer: Timer?
    private var pendingRefresh = false
    private var pricing: PricingTable = .default
    private var pricingModified: Date?
    private var cancellables: Set<AnyCancellable> = []
    private let planClient = PlanLimitClient()
    private let notifier = Notifier()
    private var planFetchInFlight = false
    private var nextPlanFetch = Date.distantPast

    init() {
        lastPlanLimitsEnabled = settings.planLimitsEnabled
        ensurePricingFile()
        startWatching()
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
        fetchPlanLimitsIfDue()
        checkThreshold()
    }

    // MARK: - Plan limitleri (resmi değil, varsayılan kapalı)

    private func fetchPlanLimitsIfDue() {
        guard settings.planLimitsEnabled, !planFetchInFlight, Date() >= nextPlanFetch else { return }
        planFetchInFlight = true
        Task {
            do {
                let limits = try await planClient.fetch()
                self.planLimits = limits
                self.planLimitError = nil
                self.nextPlanFetch = Date().addingTimeInterval(max(60, settings.refreshInterval))
            } catch {
                // Başarısızlıkta yerel veriyle devam; 5 dk sonra yeniden dene.
                self.planLimits = nil
                self.planLimitError = (error as? LocalizedError)?.errorDescription ?? "Plan limitleri alınamadı."
                self.nextPlanFetch = Date().addingTimeInterval(300)
            }
            self.planFetchInFlight = false
            self.checkThreshold()
        }
    }

    // MARK: - Bildirim

    func requestNotificationPermission() { notifier.requestAuthorization() }

    private func checkThreshold() {
        guard settings.alertEnabled else { return }
        if let w = planLimits?.fiveHour {
            let key = "official-" + (w.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "none")
            notifier.check(percent: w.utilization, threshold: settings.alertThreshold, windowKey: key, isEstimate: false)
        } else if let b = snapshot.currentBlock, let f = b.fractionOfPeakBlock {
            let key = "estimate-\(Int(b.start.timeIntervalSince1970))"
            notifier.check(percent: f * 100, threshold: settings.alertThreshold, windowKey: key, isEstimate: true)
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

    private var lastPlanLimitsEnabled = false

    private func settingsChanged() {
        scheduleTimer()
        if settings.planLimitsEnabled != lastPlanLimitsEnabled {
            lastPlanLimitsEnabled = settings.planLimitsEnabled
            if settings.planLimitsEnabled {
                nextPlanFetch = .distantPast
                fetchPlanLimitsIfDue()
            } else {
                planLimits = nil
                planLimitError = nil
                Task { await planClient.forget() }
            }
        }
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

    /// Plan limiti verisi yoksa yerel tahmine düşer ("~" ile işaretli).
    func menuBarText(mode: MenuBarMode) -> String {
        switch mode {
        case .iconOnly:
            return ""
        case .tokens:
            return Format.tokens(snapshot.summary(.today).totals.totalTokens)
        case .cost:
            return Format.cost(snapshot.summary(.today).totals.costUSD)
        case .percent:
            if let p = officialFiveHourPercent { return "\(Int(p.rounded()))%" }
            if let f = snapshot.currentBlock?.fractionOfPeakBlock { return "~\(Int((f * 100).rounded()))%" }
            return snapshot.currentBlock == nil ? "0%" : "—"
        }
    }

    /// Resmi olmayan uç noktadan gelen 5 saatlik kullanım yüzdesi (varsa).
    var officialFiveHourPercent: Double? {
        settings.planLimitsEnabled ? planLimits?.fiveHour?.utilization : nil
    }

    var displayedFiveHourPercent: Double? {
        officialFiveHourPercent ?? snapshot.currentBlock?.fractionOfPeakBlock.map { $0 * 100 }
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
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h) sa \(m) dk" : "\(m) dk"
    }
}
