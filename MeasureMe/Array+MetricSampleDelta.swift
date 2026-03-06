import Foundation
import SwiftData

extension [MetricSample] {
    /// Oblicza zmianę wartości metryki w zadanym oknie czasowym.
    /// Zwraca sformatowany string (np. "+1.2 kg") lub nil gdy brak danych lub tylko jedna próbka.
    /// Niezależna od kolejności sortowania przekazanej tablicy.
    func deltaText(
        days: Int,
        kind: MetricKind,
        unitsSystem: String,
        now: Date = AppClock.now
    ) -> String? {
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return nil }
        let window = filter { $0.date >= start }
        guard let newest = window.max(by: { $0.date < $1.date }),
              let oldest = window.min(by: { $0.date < $1.date }),
              newest.persistentModelID != oldest.persistentModelID else {
            return nil
        }
        let newestValue = kind.valueForDisplay(fromMetric: newest.value, unitsSystem: unitsSystem)
        let oldestValue = kind.valueForDisplay(fromMetric: oldest.value, unitsSystem: unitsSystem)
        let delta = newestValue - oldestValue
        return String(format: "%+.1f %@", delta, kind.unitSymbol(unitsSystem: unitsSystem))
    }
}
