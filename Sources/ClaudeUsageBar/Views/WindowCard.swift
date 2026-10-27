import SwiftUI
import UsageCore

/// Plan limitleri kartı.
struct WindowCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plan limitleri").font(.subheadline.weight(.semibold))
            Text("Veri kaynağı yok.").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
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
