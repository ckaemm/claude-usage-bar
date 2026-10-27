import SwiftUI
import UsageCore

struct PopoverView: View {
    @EnvironmentObject var model: AppModel
    @State private var period: Period = .today

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if model.snapshot.entryCount == 0, model.lastUpdated != nil, !model.isRefreshing {
                Label("Henüz Claude Code kullanım logu bulunamadı (~/.claude/projects).", systemImage: "tray")
                    .font(.caption).foregroundStyle(.secondary)
            }
            WindowCard()
            PeriodTiles(snapshot: model.snapshot)
            Divider()
            ModelBreakdown(snapshot: model.snapshot, period: $period)
            Divider()
            WeeklyChart(days: model.snapshot.last7Days)
            if let err = model.pricingError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 360)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Claude Kullanımı").font(.headline)
            Spacer()
            Badge(text: "maliyetler tahmini", tint: .secondary)
                .help("Maliyetler, yerel loglardaki token sayılarının pricing.json'daki API liste fiyatlarıyla çarpımıdır. Abonelik faturanızı yansıtmaz.")
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Group {
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                    Text("Taranıyor…")
                } else if let t = model.lastUpdated {
                    Text("Son güncelleme \(t.formatted(date: .omitted, time: .shortened))")
                } else {
                    Text("Henüz güncellenmedi")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .help("Yenile (⌘R)")
                .keyboardShortcut("r")
                .disabled(model.isRefreshing)
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

struct Badge: View {
    var text: String
    var tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(Capsule().strokeBorder(tint.opacity(0.5)))
    }
}

extension ModelFamily {
    var color: Color {
        switch self {
        case .opus: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .sonnet: return .blue
        case .haiku: return .teal
        case .fable: return .purple
        case .other: return .gray
        }
    }

    /// Grafik ve listelerde sabit sıra.
    static let displayOrder: [ModelFamily] = [.fable, .opus, .sonnet, .haiku, .other]
}
