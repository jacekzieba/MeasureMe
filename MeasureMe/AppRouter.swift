import Combine

final class AppRouter: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published var presentedSheet: PresentedSheet? = nil
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
}
