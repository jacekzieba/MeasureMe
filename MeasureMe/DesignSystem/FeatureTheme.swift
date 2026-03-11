import SwiftUI

enum FeatureTheme {
    case home
    case measurements
    case photos
    case premium
    case health
    case settings

    var accent: Color {
        switch self {
        case .home:
            return AppColorRoles.accentPrimary
        case .measurements:
            return AppColorRoles.accentData
        case .photos:
            return AppColorRoles.accentPhoto
        case .premium:
            return AppColorRoles.accentPremium
        case .health:
            return AppColorRoles.accentHealth
        case .settings:
            return AppColorRoles.accentPrimary
        }
    }

    var softTint: Color {
        accent.opacity(0.14)
    }

    var strongTint: Color {
        accent.opacity(0.22)
    }

    var border: Color {
        accent.opacity(0.24)
    }

    var pillFill: Color {
        accent.opacity(0.12)
    }

    var pillStroke: Color {
        accent.opacity(0.24)
    }
}
