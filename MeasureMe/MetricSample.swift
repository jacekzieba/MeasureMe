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
    /// Rodzaj metryki jako String (rawValue z MetricKind enum)
    /// Używane do filtrowania w Query
    var kindRaw: String
    
    /// Wartość pomiaru w jednostkach bazowych (metrycznych):
    /// - Weight/LeanBodyMass: kg
    /// - Height/Waist/inne wymiary: cm
    /// - BodyFat: % (0-100)
    var value: Double
    
    /// Data i czas pomiaru
    var date: Date

    /// Zrodlo probki: manual / HealthKit
    var sourceRaw: String = MetricSampleSource.manual.rawValue

    init(kind: MetricKind, value: Double, date: Date, source: MetricSampleSource = .manual) {
        self.kindRaw = kind.rawValue
        self.value = value
        self.date = date
        self.sourceRaw = source.rawValue
    }

    /// Inicjalizator dla custom metryk — przyjmuje surowy identyfikator (np. "custom_<UUID>")
    init(kindRaw: String, value: Double, date: Date, source: MetricSampleSource = .manual) {
        self.kindRaw = kindRaw
        self.value = value
        self.date = date
        self.sourceRaw = source.rawValue
    }

    /// Czy próbka pochodzi z custom metryki użytkownika
    var isCustomMetric: Bool {
        kindRaw.hasPrefix("custom_")
    }

    /// Wygodny accessor do konwersji String -> MetricKind.
    /// Zwraca nil dla uszkodzonych rekordów i custom metryk.
    var kind: MetricKind? {
        get { MetricKind(rawValue: kindRaw) }
        set {
            guard let newValue else { return }
            kindRaw = newValue.rawValue
        }
    }

    /// Legacy fallback: brak / nieznana wartosc traktujemy jako wpis reczny.
    var source: MetricSampleSource {
        get { MetricSampleSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}
