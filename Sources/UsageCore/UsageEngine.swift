import Foundation

/// Arka planda çalışan tarama motoru: artımlı tarama + tekilleştirme + disk önbelleği.
/// Önbellekte yalnızca sayısal kullanım verisi ve dosya ofsetleri tutulur; mesaj içeriği asla yazılmaz.
public actor UsageEngine {
    struct CacheFile: Codable {
        static let currentVersion = 1
        var version: Int
        var states: [String: FileScanState]
        var store: UsageStore
    }

    private let roots: [URL]
    private let cacheURL: URL?
    private var scanner = IncrementalScanner()
    private var store = UsageStore()
    private var loadedCache = false

    public init(roots: [URL], cacheURL: URL?) {
        self.roots = roots
        self.cacheURL = cacheURL
    }

    public static var defaultRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var roots = [home.appendingPathComponent(".claude/projects")]
        // Claude Code'un yeni sürümlerinin kullanabildiği XDG konumu.
        let xdg = home.appendingPathComponent(".config/claude/projects")
        if FileManager.default.fileExists(atPath: xdg.path) { roots.append(xdg) }
        return roots
    }

    public func refresh(pricing: PricingTable, now: Date = Date()) -> UsageSnapshot {
        if !loadedCache { loadCache() }
        let before = scanner.states
        let items = scanner.scan(roots: roots)
        let added = store.ingest(items)
        if added > 0 || scanner.states != before { saveCache() }
        return Aggregator.snapshot(store: store, pricing: pricing, now: now,
                                   malformedLines: scanner.malformedLines)
    }

    /// Önbelleği sil ve tüm logları baştan oku.
    public func rebuild(pricing: PricingTable) -> UsageSnapshot {
        scanner = IncrementalScanner()
        store = UsageStore()
        loadedCache = true
        if let cacheURL { try? FileManager.default.removeItem(at: cacheURL) }
        return refresh(pricing: pricing)
    }

    private func loadCache() {
        loadedCache = true
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(CacheFile.self, from: data),
              cache.version == CacheFile.currentVersion else { return }
        scanner = IncrementalScanner(states: cache.states)
        store = cache.store
    }

    private func saveCache() {
        guard let cacheURL else { return }
        let cache = CacheFile(version: CacheFile.currentVersion, states: scanner.states, store: store)
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
        } catch {
            // Önbellek yazılamazsa sadece bir sonraki açılış daha yavaş olur.
        }
    }
}
