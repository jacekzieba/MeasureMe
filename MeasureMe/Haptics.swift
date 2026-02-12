import UIKit

enum Haptics {
    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }

    static func selection() {
        guard isEnabled else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func light() {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    static func medium() {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    static func success() {
        guard isEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    static func error() {
        guard isEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
    }
}
