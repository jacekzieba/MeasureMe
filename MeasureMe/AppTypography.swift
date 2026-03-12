import SwiftUI

enum AppTypography {
    // MARK: - Display
    static let displayHero = Font.system(size: 34, weight: .bold, design: .rounded)
    static let displaySection = Font.system(.title2, design: .rounded).weight(.bold)
    static let displayStatement = Font.system(.title3, design: .rounded).weight(.semibold)

    // MARK: - Data
    static let dataHero = Font.system(size: 56, weight: .bold, design: .rounded).monospacedDigit()
    static let dataPrimary = Font.system(size: 48, weight: .bold, design: .rounded).monospacedDigit()
    static let dataCompact = Font.system(size: 36, weight: .bold, design: .rounded).monospacedDigit()
    static let dataValue = Font.system(.title3, design: .rounded).weight(.bold).monospacedDigit()
    static let dataDelta = Font.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit()
    static let dataLabel = Font.system(.caption, design: .default).weight(.semibold)

    // MARK: - Content
    static let titlePrimary = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let titleCompact = Font.system(.headline, design: .rounded).weight(.bold)
    static let body = Font.system(.body, design: .default)
    static let bodyEmphasis = Font.system(.body, design: .default).weight(.semibold)
    static let bodyStrong = Font.system(.subheadline, design: .default).weight(.semibold)
    static let headline = Font.system(.headline, design: .rounded)
    static let headlineEmphasis = Font.system(.headline, design: .rounded).weight(.bold)

    // MARK: - UI
    static let buttonLabel = Font.system(.subheadline, design: .default).weight(.semibold)
    static let sectionAction = Font.system(.subheadline, design: .default).weight(.semibold)
    static let caption = Font.system(.caption, design: .default)
    static let captionEmphasis = Font.system(.caption, design: .default).weight(.semibold)
    static let micro = Font.system(.caption2, design: .default)
    static let microEmphasis = Font.system(.caption2, design: .default).weight(.semibold)
    static let microBold = Font.system(.caption2, design: .default).weight(.bold)
    static let eyebrow = Font.system(.caption2, design: .default).weight(.semibold)
    static let badge = Font.system(.caption2, design: .default).weight(.bold)

    // MARK: - Backward compatibility aliases
    static let screenTitle = titlePrimary
    static let sectionTitle = displaySection
    static let metricValue = dataValue
    static let metricTitle = dataLabel
    static let displayLarge = dataHero
    static let displayMedium = dataPrimary
    static let displaySmall = dataCompact

    // MARK: - Icons (Dynamic Type–friendly sizes for SF Symbols)
    static let iconSmall = Font.system(.caption, design: .default).weight(.semibold)
    static let iconMedium = Font.system(.subheadline, design: .default).weight(.semibold)
    static let iconLarge = Font.system(.title2, design: .default).weight(.semibold)
    static let iconHero = Font.system(.title, design: .default).weight(.semibold)

}
