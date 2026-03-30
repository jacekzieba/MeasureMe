// MetricSample.swift
//
// **MetricSample**
// SwiftData model representing a single metric measurement.
//
// **Structure:**
// - Each measurement is assigned to one metric (via kindRaw)
// - Value is always in base (metric) units
// - Measurement date with minute precision
//
// **Base units:**
// - Weight (weight, leanBodyMass): kilograms (kg)
// - Dimensions (height, waist, neck, etc.): centimeters (cm)
// - Body Fat: percentage as 0.0-100.0
//
// **Unit conversion:**
// - Metric ↔ imperial conversion handled by MetricKind
// - Views always convert before display
//
import SwiftData
import Foundation

enum MetricSampleSource: String, CaseIterable, Sendable {
    case manual
    case healthKit
}

@Model
final class MetricSample {
    /// Metric kind as String (rawValue from MetricKind enum)
    /// Used for filtering in Query
    var kindRaw: String
    
    /// Measurement value in base (metric) units:
    /// - Weight/LeanBodyMass: kg
    /// - Height/Waist/other dimensions: cm
    /// - BodyFat: % (0-100)
    var value: Double
    
    /// Date and time of measurement
    var date: Date

    /// Sample source: manual / HealthKit
    var sourceRaw: String = MetricSampleSource.manual.rawValue

    init(kind: MetricKind, value: Double, date: Date, source: MetricSampleSource = .manual) {
        self.kindRaw = kind.rawValue
        self.value = value
        self.date = date
        self.sourceRaw = source.rawValue
    }

    /// Initializer for custom metrics — accepts a raw identifier (e.g. "custom_<UUID>")
    init(kindRaw: String, value: Double, date: Date, source: MetricSampleSource = .manual) {
        self.kindRaw = kindRaw
        self.value = value
        self.date = date
        self.sourceRaw = source.rawValue
    }

    /// Whether the sample belongs to a user-defined custom metric
    var isCustomMetric: Bool {
        kindRaw.hasPrefix("custom_")
    }

    /// Convenience accessor for String -> MetricKind conversion.
    /// Returns nil for corrupted records and custom metrics.
    var kind: MetricKind? {
        get { MetricKind(rawValue: kindRaw) }
        set {
            guard let newValue else { return }
            kindRaw = newValue.rawValue
        }
    }

    /// Legacy fallback: missing / unknown value is treated as a manual entry.
    var source: MetricSampleSource {
        get { MetricSampleSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}
