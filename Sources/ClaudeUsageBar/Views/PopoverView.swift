import SwiftUI
import UsageCore

struct PopoverView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Limitleri").font(.headline)
            WindowCard()
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button { model.reloadLimits() } label: { Image(systemName: "arrow.clockwise") }
                .help("Yenile (⌘R)")
                .keyboardShortcut("r")
            Button { SettingsWindow.show(model: model) } label: { Image(systemName: "gearshape") }
                .help("Ayarlar (⌘,)")
                .keyboardShortcut(",")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .help("Çıkış (⌘Q)")
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
    }
}
