import SwiftUI

enum AppTypography {
    static let screenTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let sectionTitle = Font.system(.title2, design: .rounded).weight(.bold)
    static let sectionAction = Font.system(.subheadline, design: .default).weight(.semibold)
    static let body = Font.system(.body, design: .default)
    static let bodyEmphasis = Font.system(.body, design: .default).weight(.semibold)
    static let metricValue = Font.system(.title3, design: .rounded).weight(.bold).monospacedDigit()
    static let metricTitle = Font.system(.caption, design: .default).weight(.semibold)
    static let caption = Font.system(.caption, design: .default)
    static let captionEmphasis = Font.system(.caption, design: .default).weight(.semibold)
    static let micro = Font.system(.caption2, design: .default)
    static let microEmphasis = Font.system(.caption2, design: .default).weight(.semibold)
    static let displayLarge = Font.system(size: 56, weight: .bold, design: .rounded).monospacedDigit()
    static let displayMedium = Font.system(size: 48, weight: .bold, design: .rounded).monospacedDigit()
}
