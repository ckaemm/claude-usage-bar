import SwiftUI
import UsageCore

/// 5 saatlik pencere kartı. Resmi olmayan uç nokta verisi varsa onu, yoksa yerel tahmini gösterir.
struct WindowCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        // Geri sayım her 30 sn'de bir güncellenir.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 8) {
                if let limits = model.planLimits {
                    officialView(limits, now: context.date)
                } else if let block = model.snapshot.currentBlock, block.isActive(at: context.date) {
                    estimateView(block, now: context.date)
                } else {
                    HStack {
                        Text("5 saatlik pencere").font(.subheadline.weight(.semibold))
                        Spacer()
                        Badge(text: "tahmini", tint: .secondary)
                    }
                    Text("Etkin bir oturum penceresi yok.").font(.caption).foregroundStyle(.secondary)
                }
                if let err = model.planLimitError, model.settings.planLimitsEnabled {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
        }
    }

    @ViewBuilder
    private func officialView(_ limits: PlanLimits, now: Date) -> some View {
        HStack {
            Text("Plan limitleri").font(.subheadline.weight(.semibold))
            Spacer()
            Badge(text: "resmi değil", tint: .orange)
                .help("Claude Code'un kullandığı belgelenmemiş bir uç noktadan alınır; her an değişebilir.")
        }
        ForEach(limits.windows) { w in
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(w.title).font(.caption)
                    Spacer()
                    Text("\(Int(w.utilization.rounded()))%").font(.caption.monospacedDigit().weight(.semibold))
                }
                UsageBar(fraction: w.utilization / 100)
                if let reset = w.resetsAt {
                    Text("Sıfırlanma: \(Format.countdown(to: reset, from: now)) sonra")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func estimateView(_ block: SessionBlock, now: Date) -> some View {
        HStack {
            Text("5 saatlik pencere").font(.subheadline.weight(.semibold))
            Spacer()
            Badge(text: "tahmini", tint: .secondary)
                .help("Yerel loglardan hesaplanır: pencere ilk mesajın saatinde başlar ve 5 saat sürer. Sunucudaki gerçek pencereyle birebir olmayabilir. Yüzde, geçmişteki en yüksek maliyetli 5 saatlik bloğa göredir.")
        }
        HStack(alignment: .firstTextBaseline) {
            Text(Format.tokens(block.totals.totalTokens)).font(.title3.weight(.semibold).monospacedDigit())
            Text("token · ≈ \(Format.cost(block.totals.costUSD))").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if let f = block.fractionOfPeakBlock {
                Text("~\(Int((f * 100).rounded()))%").font(.caption.monospacedDigit().weight(.semibold))
            }
        }
        if let f = block.fractionOfPeakBlock { UsageBar(fraction: f) }
        Text("Kalan: \(Format.countdown(to: block.end, from: now)) · bitiş \(block.end.formatted(date: .omitted, time: .shortened))")
            .font(.caption2).foregroundStyle(.secondary)
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
