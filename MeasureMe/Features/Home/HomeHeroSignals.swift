import SwiftUI

// MARK: - Living Pulse Hero

enum HeroPulseAction: Equatable {
    case streakDetail
    case quickAdd
    case metricDetail(MetricKind)
    case measurementsTab
    case none
}

enum HeroPulseSignalKind: String {
    case streakRisk
    case streakMilestone
    case streakActive
    case goalAchieved
    case goalNearComplete
    case returnNudge
    case trendHighlight
    case fresh
}

enum HeroPulseTint {
    case accent
    case success
    case warning
    case neutral
}

struct HeroPulseSignal {
    let kind: HeroPulseSignalKind
    let icon: String                  // SF Symbol name; ignored when useStreakBadge == true
    let title: String
    let subtitle: String
    let tint: HeroPulseTint
    let useStreakBadge: Bool
    let streakCount: Int
    let animateStreak: Bool
    let action: HeroPulseAction
}

struct HomeHeroMeasurementSnapshot {
    let label: String
    let value: String
    let detail: String
}
