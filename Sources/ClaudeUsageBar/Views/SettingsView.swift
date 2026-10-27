import AppKit
import SwiftUI
import UsageCore

/// MenuBarExtra uygulamalarında `Settings` sahnesini açmak sürüme göre değiştiği için
/// ayarlar penceresi doğrudan AppKit ile yönetilir.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(model: AppModel) {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView()
                .environmentObject(model)
                .environmentObject(model.settings))
            let w = NSWindow(contentViewController: host)
            w.title = "Claude Usage Bar Ayarları"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginMessage: String?

    var body: some View {
        Form {
            Section("Genel") {
                Picker("Menü çubuğunda göster", selection: Binding(
                    get: { settings.menuBarMode }, set: { settings.menuBarMode = $0 })) {
                    ForEach(MenuBarMode.allCases) { Text($0.title).tag($0) }
                }
                Picker("Yenileme aralığı", selection: $settings.refreshInterval) {
                    ForEach(AppSettings.refreshChoices, id: \.self) { s in
                        Text(s < 60 ? "\(Int(s)) sn" : "\(Int(s / 60)) dk").tag(s)
                    }
                }
                Text("Log dosyaları ayrıca anlık izlenir; değişiklikten ~1 sn sonra güncellenir.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Login'de otomatik başlat", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { on in
                        loginMessage = LoginItem.set(enabled: on)
                        launchAtLogin = LoginItem.isEnabled || LoginItem.requiresApproval
                    }
                if let loginMessage {
                    HStack {
                        Text(loginMessage).font(.caption).foregroundStyle(.orange)
                        Button("Aç") { LoginItem.openSystemSettings() }.controlSize(.small)
                    }
                }
            }

            Section("Uyarı") {
                Toggle("Eşik aşılınca bildirim gönder", isOn: $settings.alertEnabled)
                    .onChange(of: settings.alertEnabled) { on in if on { model.requestNotificationPermission() } }
                HStack {
                    Slider(value: $settings.alertThreshold, in: 50...100, step: 5)
                    Text("%\(Int(settings.alertThreshold))").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                .disabled(!settings.alertEnabled)
                Text("5 saatlik pencere yüzdesine göre. Plan limitleri kapalıysa yüzde yerel bir tahmindir (geçmiş en yüksek bloğa oran).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Plan limitlerini göster (resmi değil)", isOn: $settings.planLimitsEnabled)
                Text("""
                Claude Code'un kullandığı belgelenmemiş bir uç noktadan (api.anthropic.com) 5 saatlik ve haftalık limit yüzdelerini alır. \
                Açıldığında macOS, Keychain'deki "Claude Code-credentials" öğesine erişim için izin ister. Token yalnızca bellekte tutulur, \
                diske yazılmaz, loglanmaz ve başka bir yere gönderilmez. Uç nokta her an değişebilir; başarısız olursa uygulama yerel verilerle çalışmaya devam eder.
                """)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if settings.planLimitsEnabled, let err = model.planLimitError {
                    Label(err, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                } else if settings.planLimitsEnabled, let l = model.planLimits {
                    Text("Son alındı: \(l.fetchedAt.formatted(date: .omitted, time: .standard))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Plan limitleri")
            }

            Section("Veri") {
                HStack {
                    Button("Fiyat tablosunu göster") { model.openPricingFile() }
                    Button("Önbelleği sıfırla ve yeniden tara") { model.rebuild() }
                }
                Text("Fiyatlar ~/Library/Application Support/ClaudeUsageBar/pricing.json dosyasındadır (USD / 1M token). Dosyayı düzenlediğinizde bir sonraki yenilemede uygulanır.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Tekil mesaj: \(model.snapshot.entryCount.formatted()) · Okunamayan satır: \(model.snapshot.malformedLines)")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }
}
