import Foundation
import Combine

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: AppTab
    @Published var presentedSheet: PresentedSheet? = nil
    @Published private(set) var photoComposerRequestID: UUID?
    @Published private(set) var metricDetailRequestID: UUID?
    @Published private(set) var requestedMetricDetailKind: MetricKind?

    init() {
        self.selectedTab = AppRouter.defaultSelectedTab()
    }

    init(selectedTab: AppTab) {
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

    func selectTab(_ tab: AppTab) {
        selectedTab = tab
    }

    func presentComposer() {
        presentedSheet = .composer(mode: .newPost)
    }

    func presentAddSample(for kind: MetricKind) {
        presentedSheet = .addSample(kind: kind)
    }

    func dismissPresentedSheet() {
        presentedSheet = nil
    }

    func openPhotoComposer() {
        selectTab(.photos)
        requestPhotoComposer()
    }

    func openMetricDetail(_ kind: MetricKind) {
        selectTab(.measurements)
        requestedMetricDetailKind = kind
        metricDetailRequestID = UUID()
    }

    func consumePhotoComposerRequest(_ requestID: UUID) {
        guard photoComposerRequestID == requestID else { return }
        photoComposerRequestID = nil
    }

    func consumeMetricDetailRequest(_ requestID: UUID) {
        guard metricDetailRequestID == requestID else { return }
        metricDetailRequestID = nil
        requestedMetricDetailKind = nil
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
