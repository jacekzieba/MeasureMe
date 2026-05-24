import SwiftUI

// MARK: - Onboarding Card Layout

struct OnboardingCardLayout {
    let isCompact: Bool
    let headerTitleSize: CGFloat
    let sectionSpacing: CGFloat
    let groupSpacing: CGFloat
    let nameFieldFontSize: CGFloat
    let nameFieldVerticalPadding: CGFloat
    let photoWidth: CGFloat
    let photoHeight: CGFloat
    let compareChipWidth: CGFloat
    let compareChipHeight: CGFloat
    let chartRowSpacing: CGFloat

    static let regular = OnboardingCardLayout(
        isCompact: false,
        headerTitleSize: 34,
        sectionSpacing: 14,
        groupSpacing: 8,
        nameFieldFontSize: 24,
        nameFieldVerticalPadding: 8,
        photoWidth: 220,
        photoHeight: 296,
        compareChipWidth: 152,
        compareChipHeight: 38,
        chartRowSpacing: 14
    )

    static let compact = OnboardingCardLayout(
        isCompact: true,
        headerTitleSize: 30,
        sectionSpacing: 12,
        groupSpacing: 6,
        nameFieldFontSize: 22,
        nameFieldVerticalPadding: 7,
        photoWidth: 190,
        photoHeight: 264,
        compareChipWidth: 142,
        compareChipHeight: 36,
        chartRowSpacing: 12
    )
}

// MARK: - Intro Metrics Layout

enum IntroMetricsLayout {
    static let columnSpacing: CGFloat = 12
    static let cardPadding: CGFloat = 12
    static let chartCardHeight: CGFloat = 186
    static let compactChartCardHeight: CGFloat = 164
    static let chartHeight: CGFloat = 78
    static let compactChartHeight: CGFloat = 62
    static let legendHeight: CGFloat = 16
    static let valueBlockHeight: CGFloat = 42
    static let compactValueBlockHeight: CGFloat = 36
}

// MARK: - Dummy Chart Legend Item

struct DummyChartLegendItem {
    let label: String
    let color: Color
}

// MARK: - Metrics Preview Card Data

struct MetricsPreviewCardData {
    let title: String
    let value: String
    let delta: String
    let tint: Color
    let backgroundTint: Color
    let points: [CGPoint]
}

// MARK: - Metrics Insight Copy

struct MetricsInsightCopy {
    let title: String
    let lineOne: String
    let lineTwo: String
    let tip: String
}
