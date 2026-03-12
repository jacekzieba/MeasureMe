import Foundation
import Combine

final class AppRouter: ObservableObject {
    @Published var selectedTab: AppTab
    @Published var presentedSheet: PresentedSheet? = nil

    init(selectedTab: AppTab = AppRouter.defaultSelectedTab()) {
        self.selectedTab = selectedTab
    }

    private static func defaultSelectedTab() -> AppTab {
        if ProcessInfo.processInfo.arguments.contains("-uiTestOpenSettingsTab") {
            return .settings
        }
        return .home
    }
}

enum PresentedSheet: Identifiable {
    case composer(mode: ComposerMode)
    case addSample(kind: MetricKind)

    var id: String {
        switch self {
        case .composer(let mode):
            return "composer-\(mode.rawValue)"
        case .addSample(let kind):
            return "addSample-\(kind.rawValue)"
        }
    }
}

enum ComposerMode: String {
    case newPost = "newPost"
}
