// MetricSample.swift
//
// **MetricSample**
// Model SwiftData reprezentujący pojedynczy pomiar metryki.
//
// **Struktura:**
// - Każdy pomiar przypisany do jednej metryki (przez kindRaw)
// - Wartość zawsze w jednostkach bazowych (metrycznych)
// - Data pomiaru z dokładnością do minuty
//
// **Jednostki bazowe:**
// - Waga (weight, leanBodyMass): kilogramy (kg)
// - Wymiary (height, waist, neck, itp.): centymetry (cm)  
// - Body Fat: procent jako 0.0-100.0
//
// **Konwersja jednostek:**
// - Konwersja metric ↔ imperial obsługiwana przez MetricKind
// - Widoki zawsze konwertują przed wyświetleniem
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
