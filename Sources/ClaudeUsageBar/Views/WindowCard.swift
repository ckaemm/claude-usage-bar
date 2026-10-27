import SwiftUI
import UsageCore

/// Plan limitleri kartı: Claude Code status line'ından gelen 5 saatlik ve haftalık yüzdeler.
struct WindowCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        // Geri sayım ve "x dk önce" metni her 30 sn'de bir güncellenir.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 8) {
                if let limits = model.limits {
                    if let w = limits.fiveHour { row("5 saatlik oturum", w, now: now) }
                    if let w = limits.sevenDay { row("Haftalık", w, now: now) }
                    Text("Güncellendi: \(Format.ago(limits.capturedAt, now: now))")
                        .font(.caption2).foregroundStyle(.secondary)
                    if limits.isStale(at: now) { updatesNote }
                } else {
                    updatesNote
                    if model.isStatusLineInstalled {
                        Text("Bu alanlar yalnızca Claude Pro/Max hesabıyla girişte gelir; API anahtarıyla girişte gelmez.")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack {
                            Text("Claude Code status line köprüsü kurulu değil.")
                                .font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Button("Kur…") { SettingsWindow.show(model: model) }
                                .controlSize(.small)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
        }
    }

    private var updatesNote: some View {
        Label("Claude Code çalışırken güncellenir.", systemImage: "info.circle")
            .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func row(_ title: String, _ w: RateLimitWindow, now: Date) -> some View {
        let expired = w.isExpired(at: now)
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(expired ? "—" : "%\(Int(w.usedPercentage.rounded()))")
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
            UsageBar(fraction: expired ? 0 : w.usedPercentage / 100)
            if expired {
                Text("Pencere sıfırlandı; yeni değer Claude Code'daki bir sonraki yanıtla gelir.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if let reset = w.resetsAt {
                Text("Sıfırlanma: \(Format.countdown(to: reset, from: now)) sonra · \(reset.formatted(date: Calendar.current.isDate(reset, inSameDayAs: now) ? .omitted : .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct UsageBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(tint).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 6)
        .accessibilityValue("\(Int((fraction * 100).rounded())) yüzde")
    }

    private var tint: Color {
        switch fraction {
        case ..<0.6: return .green
        case ..<0.85: return .orange
        default: return .red
        }
    }
}
