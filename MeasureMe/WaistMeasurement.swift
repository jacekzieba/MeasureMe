// WaistMeasurement.swift
// Model danych SwiftData dla pomiaru obwodu talii
// Model danych dla pojedynczego pomiaru obwodu talii.
import SwiftData
import Foundation

/// Reprezentuje zapis pomiaru obwodu talii z wartością i datą.
@Model
class WaistMeasurement {
    /// Wartość w cm
    var value: Double
    /// Data pomiaru
    var date: Date

    /// Inicjalizacja modelu
    init(value: Double, date: Date) {
        self.value = value
        self.date = date
    }
    
}

