import Foundation
import Combine

final class AppRouter: ObservableObject {
    @Published var selectedTab: AppTab
    @Published var presentedSheet: PresentedSheet? = nil
    @Published private(set) var photoComposerRequestID: UUID?

    init(selectedTab: AppTab = AppRouter.defaultSelectedTab()) {
        self.selectedTab = selectedTab
    }

    private static func defaultSelectedTab() -> AppTab {
        if UITestArgument.isPresent(.openSettingsTab) {
            return .settings
        }
        return .home
    }

    func requestPhotoComposer() {
        photoComposerRequestID = UUID()
    }

    func consumePhotoComposerRequest(_ requestID: UUID) {
        guard photoComposerRequestID == requestID else { return }
        photoComposerRequestID = nil
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
