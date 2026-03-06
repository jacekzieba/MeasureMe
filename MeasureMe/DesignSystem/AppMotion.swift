import SwiftUI

enum AppMotion {
    static func shouldAnimate(animationsEnabled: Bool, reduceMotion: Bool) -> Bool {
        animationsEnabled && !reduceMotion
    }

    static func animation(_ animation: Animation, enabled: Bool) -> Animation? {
        enabled ? animation : nil
    }

    static func repeating(_ animation: Animation, enabled: Bool) -> Animation? {
        enabled ? animation : nil
    }

    static let quick = Animation.easeOut(duration: 0.18)
    static let standard = Animation.easeInOut(duration: 0.28)
    static let emphasized = Animation.spring(response: 0.4, dampingFraction: 0.88)
    static let reveal = Animation.easeOut(duration: 0.35)
    static let sectionEnter = Animation.spring(response: 0.36, dampingFraction: 0.9)
    static let sectionExit = Animation.easeInOut(duration: 0.22)
    static let numericUpdate = Animation.easeInOut(duration: 0.24)
    static let microFeedback = Animation.easeOut(duration: 0.14)
    static let toastIn = Animation.easeOut(duration: 0.15)
    static let toastOut = Animation.easeIn(duration: 0.2)
    static let pulse = Animation.easeInOut(duration: 1.25).repeatForever(autoreverses: true)
}
