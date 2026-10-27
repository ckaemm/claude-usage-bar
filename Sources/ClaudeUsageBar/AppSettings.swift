import Foundation
import SwiftUI

enum MenuBarMode: String, CaseIterable, Identifiable {
    case percent, tokens, cost, iconOnly
    var id: String { rawValue }

    var title: String {
        switch self {
        case .percent: return "Yüzde (5 sa pencere)"
        case .tokens: return "Bugünkü token"
        case .cost: return "Bugünkü tahmini maliyet"
        case .iconOnly: return "Yalnızca ikon"
        }
    }
}

/// Kullanıcı ayarları (UserDefaults). Gizli veri içermez.
final class AppSettings: ObservableObject {
    @AppStorage("refreshInterval") var refreshInterval: Double = 60
    @AppStorage("menuBarMode") var menuBarModeRaw: String = MenuBarMode.tokens.rawValue
    @AppStorage("alertEnabled") var alertEnabled: Bool = false
    @AppStorage("alertThreshold") var alertThreshold: Double = 80

    var menuBarMode: MenuBarMode {
        get { MenuBarMode(rawValue: menuBarModeRaw) ?? .tokens }
        set { menuBarModeRaw = newValue.rawValue }
    }

    static let refreshChoices: [Double] = [30, 60, 120, 300]
}
