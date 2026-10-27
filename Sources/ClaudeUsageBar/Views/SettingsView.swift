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
    /// Onay bekleyen mevcut status line komutu.
    @State private var pendingWrapCommand: String?

    var body: some View {
        Form {
            Section("Genel") {
                Picker("Menü çubuğunda göster", selection: Binding(
                    get: { settings.menuBarMode }, set: { settings.menuBarMode = $0 })) {
                    ForEach(MenuBarMode.allCases) { Text($0.title).tag($0) }
                }
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

            Section {
                statusLineRow
                Text("""
                Claude Code'un status line ayarına küçük bir script bağlar. Script, Claude Code'un ona verdiği \
                5 saatlik ve haftalık limit yüzdelerini ~/.claude-usage-bar/limits/ klasörüne (oturum başına bir dosya) yazar; \
                uygulama bu dosyayı okur. Yüzdeler yalnızca Claude Pro/Max girişinde ve Claude Code çalışırken güncellenir. \
                ~/.claude/settings.json içinde yalnızca statusLine ayarı değişir ve önce yedek alınır.
                """)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if let msg = model.statusLineMessage {
                    Text(msg).font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Claude Code bağlantısı")
            }

            Section("Uyarı") {
                Toggle("Eşik aşılınca bildirim gönder", isOn: $settings.alertEnabled)
                    .onChange(of: settings.alertEnabled) { on in if on { model.requestNotificationPermission() } }
                HStack {
                    Slider(value: $settings.alertThreshold, in: 50...100, step: 5)
                    Text("%\(Int(settings.alertThreshold))").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                .disabled(!settings.alertEnabled)
                Text("5 saatlik ve haftalık limit yüzdelerine göre; pencere başına bir bildirim.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            launchAtLogin = LoginItem.isEnabled
            model.statusLineMessage = nil
            model.reloadStatusLineStatus()
        }
        .alert("Mevcut status line ayarı", isPresented: Binding(
            get: { pendingWrapCommand != nil }, set: { if !$0 { pendingWrapCommand = nil } })) {
            Button("Sarmala ve kur") { model.installStatusLine(confirmedWrapping: true) }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("""
            ~/.claude/settings.json içinde zaten bir status line var:

            \(pendingWrapCommand ?? "")

            Kurulum bunun üzerine yazmaz: script önce mevcut komutu çalıştırıp çıktısını aynen gösterir, \
            sonra yalnızca limit verisini kaydeder. "Kaldır" ile eski ayar geri yüklenir.
            """)
        }
    }

    @ViewBuilder
    private var statusLineRow: some View {
        HStack {
            switch model.statusLineStatus {
            case .installed(let wrapping):
                Label("Kurulu", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                if let wrapping {
                    Text("(sarmalanan: \(wrapping))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Kaldır") { model.uninstallStatusLine() }
            case .notInstalled:
                Label("Kurulu değil", systemImage: "circle.dashed").foregroundStyle(.secondary)
                Spacer()
                Button("Kur") { pendingWrapCommand = model.installStatusLine() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
