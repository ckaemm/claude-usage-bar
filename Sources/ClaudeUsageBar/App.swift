import SwiftUI
import UsageCore

struct ClaudeUsageBarApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(model)
                .environmentObject(model.settings)
        } label: {
            MenuBarLabel(model: model, settings: model.settings)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Menü çubuğunda görünen ikon + kısa metin.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        let text = model.menuBarText(mode: settings.menuBarMode)
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.33percent")
            if !text.isEmpty { Text(text).monospacedDigit() }
        }
    }
}

enum AppPaths {
    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ClaudeUsageBar", isDirectory: true)
    }
    static var pricingURL: URL { supportDir.appendingPathComponent("pricing.json") }
    static var cacheURL: URL { supportDir.appendingPathComponent("cache.json") }
}
