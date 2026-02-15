import Combine

final class AppRouter: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published var presentedSheet: PresentedSheet? = nil
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
