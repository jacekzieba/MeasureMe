import SwiftUI

enum AppTab: Int, CaseIterable {
    case home = 0
    case measurements = 1
    case compose = 2
    case photos = 3
    case settings = 4

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .measurements:
            return "Measurements"
        case .photos:
            return "Photos"
        case .compose:
            return "Add"
        case .settings:
            return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home:
            return "house.fill"
        case .measurements:
            return "ruler"
        case .photos:
            return "photo"
        case .compose:
            return "plus.circle.fill"
        case .settings:
            return "gearshape"
        }
    }
}
