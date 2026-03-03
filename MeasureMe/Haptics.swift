import UIKit

enum Haptics {
    enum HapticEvent {
        case selection
        case confirmSoft
        case success
        case error
        case warningSoft
        case densityStep
    }

    private static let throttleInterval: TimeInterval = 0.04
    private static var lastEventAt: CFTimeInterval = 0
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let rigidImpactGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    private static var isEnabled: Bool {
        AppSettingsStore.shared.snapshot.experience.hapticsEnabled
    }

    static func trigger(_ event: HapticEvent) {
        guard isEnabled else { return }

        if Thread.isMainThread {
            triggerOnMain(event)
        } else {
            DispatchQueue.main.async {
                triggerOnMain(event)
            }
        }
    }

    private static func triggerOnMain(_ event: HapticEvent) {
        let now = CACurrentMediaTime()
        if now - lastEventAt < throttleInterval, shouldThrottle(event) {
            return
        }
        lastEventAt = now

        switch event {
        case .selection:
            selectionGenerator.prepare()
            selectionGenerator.selectionChanged()
        case .confirmSoft:
            lightImpactGenerator.prepare()
            lightImpactGenerator.impactOccurred()
        case .success:
            notificationGenerator.prepare()
            notificationGenerator.notificationOccurred(.success)
        case .error:
            notificationGenerator.prepare()
            notificationGenerator.notificationOccurred(.error)
        case .warningSoft:
            rigidImpactGenerator.prepare()
            rigidImpactGenerator.impactOccurred(intensity: 0.55)
        case .densityStep:
            mediumImpactGenerator.prepare()
            mediumImpactGenerator.impactOccurred(intensity: 0.6)
        }
    }

    private static func shouldThrottle(_ event: HapticEvent) -> Bool {
        switch event {
        case .selection, .confirmSoft, .warningSoft, .densityStep:
            return true
        case .success, .error:
            return false
        }
    }

    static func selection() {
        trigger(.selection)
    }

    static func light() {
        trigger(.confirmSoft)
    }

    static func medium() {
        trigger(.densityStep)
    }

    static func success() {
        trigger(.success)
    }

    static func error() {
        trigger(.error)
    }
}
