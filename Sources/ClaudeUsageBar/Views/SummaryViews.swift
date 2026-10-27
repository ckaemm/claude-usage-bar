import Charts
import SwiftUI
import UsageCore

/// Bugün / Bu hafta / Bu ay özet kutucukları.
struct PeriodTiles: View {
    var snapshot: UsageSnapshot

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Period.allCases) { p in
                let t = snapshot.summary(p).totals
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.rawValue).font(.caption).foregroundStyle(.secondary)
                    Text(Format.tokens(t.totalTokens)).font(.headline.monospacedDigit())
                    Text("≈ \(Format.cost(t.costUSD))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
                .help(tooltip(t))
            }
        }
    }

    private func tooltip(_ t: Totals) -> String {
        var s = """
        Giriş: \(t.inputTokens.formatted())
        Çıkış: \(t.outputTokens.formatted())
        Cache yazma: \(t.cacheWriteTokens.formatted())
        Cache okuma: \(t.cacheReadTokens.formatted())
        Mesaj: \(t.messageCount.formatted())
        """
        if t.unpricedTokens > 0 { s += "\nFiyatı bilinmeyen: \(t.unpricedTokens.formatted()) token" }
        return s
    }
}

/// Seçilen dönem için model ailesi dağılımı.
struct ModelBreakdown: View {
    var snapshot: UsageSnapshot
    @Binding var period: Period

    var body: some View {
        let summary = snapshot.summary(period)
        let rows = ModelFamily.displayOrder.compactMap { f in summary.byFamily[f].map { (f, $0) } }
        let maxTokens = rows.map(\.1.totalTokens).max() ?? 0

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Model dağılımı").font(.subheadline.weight(.semibold))
                Spacer()
                Picker("", selection: $period) {
                    ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
            }
            if rows.isEmpty {
                Text("Bu dönemde kullanım yok.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.0) { family, t in
                HStack(spacing: 8) {
                    Circle().fill(family.color).frame(width: 8, height: 8)
                    Text(family.rawValue).font(.caption).frame(width: 48, alignment: .leading)
                    GeometryReader { geo in
                        Capsule().fill(family.color.opacity(0.8))
                            .frame(width: max(2, geo.size.width * Double(t.totalTokens) / Double(max(1, maxTokens))))
                    }
                    .frame(height: 6)
                    Text(Format.tokens(t.totalTokens)).font(.caption.monospacedDigit()).frame(width: 52, alignment: .trailing)
                    Text(Format.cost(t.costUSD)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }
            if snapshot.hasSupplementalData {
                Text("Claude Code'un iç çağrıları (ör. Haiku) oturum özetinden eklenir; zamanlaması yaklaşıktır.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

/// Son 7 günün model ailesine göre yığılmış token grafiği.
struct WeeklyChart: View {
    var days: [DayBucket]

    private struct Point: Identifiable {
        var label: String
        var family: ModelFamily
        var tokens: Int
        var id: String { "\(label)-\(family.rawValue)" }
    }

    /// Kategorik eksen: 7 günün kısa adları (son 7 günde her ad tekildir).
    private var labels: [String] {
        days.map { $0.date.formatted(.dateTime.weekday(.abbreviated)) }
    }

    var body: some View {
        let labels = self.labels
        let points = zip(days, labels).flatMap { d, label in
            ModelFamily.displayOrder.compactMap { f in
                d.byFamily[f].map { Point(label: label, family: f, tokens: $0.totalTokens) }
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Son 7 gün").font(.subheadline.weight(.semibold))
                Spacer()
                let total = days.reduce(0.0) { $0 + $1.totals.costUSD }
                Text("≈ \(Format.cost(total))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Chart(points) { p in
                BarMark(
                    x: .value("Gün", p.label),
                    y: .value("Token", p.tokens),
                    width: .ratio(0.6)
                )
                .foregroundStyle(by: .value("Model", p.family.rawValue))
            }
            .chartForegroundStyleScale(
                domain: ModelFamily.displayOrder.map(\.rawValue),
                range: ModelFamily.displayOrder.map(\.color))
            .chartLegend(.hidden)
            .chartXScale(domain: labels)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                    AxisGridLine()
                    AxisValueLabel { if let n = v.as(Int.self) { Text(Format.tokens(n)) } }
                }
            }
            .frame(height: 110)
            .overlay {
                if points.isEmpty {
                    Text("Son 7 günde kullanım yok").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
