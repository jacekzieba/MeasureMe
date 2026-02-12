import SwiftUI
import Observation

@Observable
class AppRouter {
    var selectedTab: AppTab = .home
    var presentedSheet: PresentedSheet? = nil
}

enum PresentedSheet: Identifiable {
    case composer(mode: ComposerMode)

    var id: String {
        switch self {
        case .composer(let mode):
            return "composer-\(mode.rawValue)"
        }
    }
}

enum ComposerMode: String {
    case newPost = "newPost"
    case editPost = "editPost"
}
