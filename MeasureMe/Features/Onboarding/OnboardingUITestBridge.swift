import Foundation
import Combine

@MainActor
final class OnboardingUITestBridge: ObservableObject {
    static let shared = OnboardingUITestBridge()

    @Published private(set) var currentStepIndex: Int = 0
    @Published private(set) var iCloudViewed: Bool = false
    @Published private(set) var iCloudSkipped: Bool = false
    @Published private(set) var iCloudEnabled: Bool = false

    func update(
        currentStepIndex: Int,
        iCloudViewed: Bool,
        iCloudSkipped: Bool,
        iCloudEnabled: Bool
    ) {
        self.currentStepIndex = currentStepIndex
        self.iCloudViewed = iCloudViewed
        self.iCloudSkipped = iCloudSkipped
        self.iCloudEnabled = iCloudEnabled
    }
}

extension Notification.Name {
    static let onboardingUITestNext = Notification.Name("OnboardingUITestNext")
    static let onboardingUITestBack = Notification.Name("OnboardingUITestBack")
    static let onboardingUITestSkip = Notification.Name("OnboardingUITestSkip")
}
