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

    init(kind: MetricKind, value: Double, date: Date) {
        self.kindRaw = kind.rawValue
        self.value = value
        self.date = date
    }

    /// Wygodny accessor do konwersji String -> MetricKind
    var kind: MetricKind {
        get { MetricKind(rawValue: kindRaw) ?? .weight }
        set { kindRaw = newValue.rawValue }
    }
}
