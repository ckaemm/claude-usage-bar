import Foundation
import SwiftUI

enum MenuBarMode: String, CaseIterable, Identifiable {
    case both, fiveHour, iconOnly
    var id: String { rawValue }

    var title: String {
        switch self {
        case .both: return "5 saatlik ve haftalık"
        case .fiveHour: return "Yalnızca 5 saatlik"
        case .iconOnly: return "Yalnızca ikon"
        }
    }
}

/// Kullanıcı ayarları (UserDefaults). Gizli veri içermez.
final class AppSettings: ObservableObject {
    @AppStorage("menuBarMode.v2") var menuBarModeRaw: String = MenuBarMode.both.rawValue
    @AppStorage("alertEnabled") var alertEnabled: Bool = false
    @AppStorage("alertThreshold") var alertThreshold: Double = 80

    var menuBarMode: MenuBarMode {
        get { MenuBarMode(rawValue: menuBarModeRaw) ?? .both }
        set { menuBarModeRaw = newValue.rawValue }
    }
}
