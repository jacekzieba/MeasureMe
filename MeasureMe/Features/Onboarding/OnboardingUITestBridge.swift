import Foundation
import Combine

@MainActor
final class OnboardingUITestBridge: ObservableObject {
    static let shared = OnboardingUITestBridge()

    @Published private(set) var currentStepIndex: Int = 0

    func update(currentStepIndex: Int) {
        self.currentStepIndex = currentStepIndex
    }
}

extension Notification.Name {
    static let onboardingUITestNext = Notification.Name("OnboardingUITestNext")
    static let onboardingUITestBack = Notification.Name("OnboardingUITestBack")
    static let onboardingUITestSkip = Notification.Name("OnboardingUITestSkip")
}
