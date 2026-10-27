import Foundation
import ServiceManagement

/// Login'de otomatik başlatma (SMAppService, macOS 13+).
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// - Returns: kullanıcıya gösterilecek hata mesajı (varsa).
    static func set(enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            if requiresApproval {
                return "Sistem Ayarları › Genel › Giriş Öğeleri'nden onay vermeniz gerekiyor."
            }
            return nil
        } catch {
            return "Giriş öğesi ayarlanamadı: \(error.localizedDescription). Uygulamayı /Applications altına taşıyıp tekrar deneyin."
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
