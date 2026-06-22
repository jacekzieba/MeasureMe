import SwiftUI
import Foundation

// MARK: - Timeframe

/// Zakresy czasowe dla wykresu
enum Timeframe: String, CaseIterable, Identifiable {
    case week = "7D"
    case month = "30D"
    case threeMonths = "90D"
    case year = "1Y"
    case all = "All"
    var id: String { rawValue }

    var relativeTrendLocalizationKey: String {
        switch self {
        case .week: return "trend.relative.7d"
        case .month: return "trend.relative.30d"
        case .threeMonths: return "trend.relative.90d"
        case .year: return "trend.relative.1y"
        case .all: return "trend.relative.all"
        }
    }

    /// Calculates the start date for a given time range
    /// - Parameter now: Reference date (defaults to now)
    /// - Returns: Start date or nil for "All"
    func startDate(from now: Date = AppClock.now) -> Date? {
        let cal = Calendar.current
        switch self {
        case .week: return cal.date(byAdding: .day, value: -7, to: now)
        case .month: return cal.date(byAdding: .day, value: -30, to: now)
        case .threeMonths: return cal.date(byAdding: .day, value: -90, to: now)
        case .year: return cal.date(byAdding: .year, value: -1, to: now)
        case .all: return nil
        }
    }
}

extension Timeframe {
    var minimumRenderPointLimit: Int {
        switch self {
        case .week: return 56
        case .month: return 72
        case .threeMonths: return 84
        case .year: return 96
        case .all: return 112
        }
    }

    var maximumRenderPointLimit: Int {
        switch self {
        case .week: return 220
        case .month: return 240
        case .threeMonths: return 260
        case .year: return 280
        case .all: return 320
        }
    }
}

// MARK: - Chart Scrub State

enum ChartScrubState {
    case idle
    case armed
    case scrubbing
}

// MARK: - Insight State

enum InsightState {
    case loading
    case ready(String)
    case fallback(String)
}

// MARK: - Comparison Cache

struct ComparisonCache {
    var options: [MetricComparisonOption] = []
    var samplesByKind: [MetricKind: [MetricSample]] = [:]
}

// MARK: - Trend Period

struct TrendPeriod: Identifiable {
    let days: Int?
    let labelKey: String
    var id: String { labelKey }
}
