import SwiftUI

enum AppTypography {
    // MARK: - Titles
    static let screenTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let sectionTitle = Font.system(.title2, design: .rounded).weight(.bold)
    static let sectionAction = Font.system(.subheadline, design: .default).weight(.semibold)

    // MARK: - Body
    static let body = Font.system(.body, design: .default)
    static let bodyEmphasis = Font.system(.body, design: .default).weight(.semibold)
    static let headline = Font.system(.headline, design: .rounded)
    static let headlineEmphasis = Font.system(.headline, design: .rounded).weight(.bold)

    // MARK: - Metric Values
    static let metricValue = Font.system(.title3, design: .rounded).weight(.bold).monospacedDigit()
    static let metricTitle = Font.system(.caption, design: .default).weight(.semibold)

    // MARK: - Captions
    static let caption = Font.system(.caption, design: .default)
    static let captionEmphasis = Font.system(.caption, design: .default).weight(.semibold)
    static let micro = Font.system(.caption2, design: .default)
    static let microEmphasis = Font.system(.caption2, design: .default).weight(.semibold)
    static let microBold = Font.system(.caption2, design: .default).weight(.bold)

    // MARK: - Display (large numeric values – keep fixed size for layout stability)
    static let displayLarge = Font.system(size: 56, weight: .bold, design: .rounded).monospacedDigit()
    static let displayMedium = Font.system(size: 48, weight: .bold, design: .rounded).monospacedDigit()
    static let displaySmall = Font.system(size: 36, weight: .bold, design: .rounded).monospacedDigit()

    // MARK: - Icons (Dynamic Type–friendly sizes for SF Symbols)
    static let iconSmall = Font.system(.caption, design: .default).weight(.semibold)
    static let iconMedium = Font.system(.subheadline, design: .default).weight(.semibold)
    static let iconLarge = Font.system(.title2, design: .default).weight(.semibold)
    static let iconHero = Font.system(.title, design: .default).weight(.semibold)
}
