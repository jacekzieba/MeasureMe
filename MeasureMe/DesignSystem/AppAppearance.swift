import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var title: String {
        switch self {
        case .system:
            return AppLocalization.string("System")
        case .light:
            return AppLocalization.string("Light")
        case .dark:
            return AppLocalization.string("Dark")
        }
    }

    var settingsSummaryKey: String {
        switch self {
        case .system:
            return "settings.summary.appearance.system"
        case .light:
            return "settings.summary.appearance.light"
        case .dark:
            return "settings.summary.appearance.dark"
        }
    }
}
