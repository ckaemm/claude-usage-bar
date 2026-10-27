import Foundation
import UsageCore

// `ClaudeUsageBar --dump`: UI açmadan tüm logları tarar ve özeti yazdırır (doğrulama/hata ayıklama için).
if CommandLine.arguments.contains("--dump") {
    let started = Date()
    let engine = UsageEngine(roots: UsageEngine.defaultRoots, cacheURL: nil)
    let pricing = (try? PricingTable.load(from: AppPaths.pricingURL)) ?? .default
    Task {
        let s = await engine.refresh(pricing: pricing)
        let elapsed = Date().timeIntervalSince(started)
        print("Tarama süresi: \(String(format: "%.2f", elapsed)) sn, tekil mesaj: \(s.entryCount), bozuk satır: \(s.malformedLines)")
        for p in Period.allCases {
            let t = s.summary(p).totals
            print("\(p.rawValue): \(t.totalTokens) token (giriş \(t.inputTokens), çıkış \(t.outputTokens), cache yazma \(t.cacheWriteTokens), cache okuma \(t.cacheReadTokens)) ≈ $\(String(format: "%.4f", t.costUSD))")
            for (fam, ft) in s.summary(p).byFamily.sorted(by: { $0.value.totalTokens > $1.value.totalTokens }) {
                print("   \(fam.rawValue): \(ft.totalTokens) token ≈ $\(String(format: "%.4f", ft.costUSD))")
            }
        }
        if let b = s.currentBlock {
            print("Etkin 5 sa blok: \(b.start) → \(b.end), \(b.totals.totalTokens) token, tepe oranı \(b.fractionOfPeakBlock.map { String(format: "%.0f%%", $0 * 100) } ?? "-")")
        }
        exit(0)
    }
    dispatchMain()
} else {
    ClaudeUsageBarApp.main()
}
