import Foundation

/// Snapshot wartości metryk zapisany razem ze zdjęciem
/// Używany do:
/// - porównań (Compare)
/// - eksportu obrazów
/// - zachowania kontekstu historycznego
struct MetricValueSnapshot: Codable, Identifiable {

    let id: UUID
    let metricRawValue: String
    let value: Double
    let unit: String

    var kind: MetricKind? {
        MetricKind(rawValue: metricRawValue)
    }

    init(
        id: UUID = UUID(),
        kind: MetricKind,
        value: Double,
        unit: String
    ) {
        self.id = id
        self.metricRawValue = kind.rawValue
        self.value = value
        self.unit = unit
    }

    init(
        id: UUID = UUID(),
        metricRawValue: String,
        value: Double,
        unit: String
    ) {
        self.id = id
        self.metricRawValue = metricRawValue
        self.value = value
        self.unit = unit
    }
}
