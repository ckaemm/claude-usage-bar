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
        exit(0)
    }
    dispatchMain()
} else if CommandLine.arguments.contains("--install-statusline") || CommandLine.arguments.contains("--uninstall-statusline") {
    // Terminalden kurulum/kaldırma. Mevcut bir status line'ı sarmalamak için --wrap gerekir.
    let installer = StatusLineInstaller.default
    do {
        if CommandLine.arguments.contains("--uninstall-statusline") {
            try installer.uninstall()
            print("Status line köprüsü kaldırıldı.")
        } else {
            try installer.install(confirmedWrapping: CommandLine.arguments.contains("--wrap"))
            print("Status line köprüsü kuruldu: \(installer.scriptURL.path)")
        }
        exit(0)
    } catch StatusLineInstaller.InstallError.needsConfirmation(let cmd) {
        print("Mevcut bir status line var: \(cmd)\nÜzerine yazılmadı. Sarmalamak için: --install-statusline --wrap")
        exit(1)
    } catch {
        print("Hata: \(error.localizedDescription)")
        exit(1)
    }
} else {
    ClaudeUsageBarApp.main()
}
