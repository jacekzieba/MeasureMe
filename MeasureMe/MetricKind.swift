// MetricKind.swift
//
// **MetricKind**
// Główny enum definiujący wszystkie rodzaje metryk w aplikacji.
//
// **Odpowiedzialności:**
// - Definicja wszystkich dostępnych metryk
// - Dostarczanie metadanych (tytuł, ikona, jednostki)
// - Konwersja jednostek metric ↔ imperial
// - Klasyfikacja metryk (weight, length, percent)
//
// **Kategorie metryk:**
// - Body Composition: weight, bodyFat, leanBodyMass
// - Body Size: height, waist
// - Upper Body: neck, shoulders, bust, chest
// - Arms: biceps, forearms (left & right)
// - Lower Body: hips, thighs, calves (left & right)
//
import Foundation

enum MetricKind: String, CaseIterable, Hashable, Identifiable {
    var id: String { rawValue }

    // MARK: - Body Composition & Size
    case weight
    case bodyFat
    case height
    case leanBodyMass
    case waist

    // MARK: - Upper Body
    case neck
    case shoulders
    case bust
    case chest
    
    // MARK: - Arms
    case leftBicep
    case rightBicep
    case leftForearm
    case rightForearm
    
    // MARK: - Lower Body
    case hips
    case leftThigh
    case rightThigh
    case leftCalf
    case rightCalf

    // MARK: - Display Properties
    
    /// Czytelna nazwa metryki dla UI
    var title: String {
        switch self {
        case .weight: return AppLocalization.string("metric.weight")
        case .bodyFat: return AppLocalization.string("metric.bodyfat")
        case .height: return AppLocalization.string("metric.height")
        case .leanBodyMass: return AppLocalization.string("metric.leanbodymass")
        case .waist: return AppLocalization.string("metric.waist")
        case .neck: return AppLocalization.string("metric.neck")
        case .shoulders: return AppLocalization.string("metric.shoulders")
        case .bust: return AppLocalization.string("metric.bust")
        case .chest: return AppLocalization.string("metric.chest")
        case .leftBicep: return AppLocalization.string("metric.leftbicep")
        case .rightBicep: return AppLocalization.string("metric.rightbicep")
        case .leftForearm: return AppLocalization.string("metric.leftforearm")
        case .rightForearm: return AppLocalization.string("metric.rightforearm")
        case .hips: return AppLocalization.string("metric.hips")
        case .leftThigh: return AppLocalization.string("metric.leftthigh")
        case .rightThigh: return AppLocalization.string("metric.rightthigh")
        case .leftCalf: return AppLocalization.string("metric.leftcalf")
        case .rightCalf: return AppLocalization.string("metric.rightcalf")
        }
    }

    /// English title for AI prompts / internal logic
    var englishTitle: String {
        switch self {
        case .weight: return "Weight"
        case .bodyFat: return "Body fat"
        case .height: return "Height"
        case .leanBodyMass: return "Lean body mass"
        case .waist: return "Waist"
        case .neck: return "Neck"
        case .shoulders: return "Shoulders"
        case .bust: return "Bust"
        case .chest: return "Chest"
        case .leftBicep: return "Left bicep"
        case .rightBicep: return "Right bicep"
        case .leftForearm: return "Left forearm"
        case .rightForearm: return "Right forearm"
        case .hips: return "Hips"
        case .leftThigh: return "Left thigh"
        case .rightThigh: return "Right thigh"
        case .leftCalf: return "Left calf"
        case .rightCalf: return "Right calf"
        }
    }

    /// Nazwa ikony SF Symbols dla metryki
    var systemImage: String {
        switch self {
        case .weight: return "scalemass.fill"
        case .bodyFat: return "figure.arms.open"
        case .height: return "figure.stand"
        case .leanBodyMass: return "figure.strengthtraining.traditional"
        case .waist: return "figure.cooldown"

        case .neck: return "person.crop.square"
        case .shoulders: return "person.fill"
        case .bust: return "figure.stand.dress"
        case .chest: return "figure"

        case .leftBicep, .rightBicep: return "figure.martial.arts"
        case .leftForearm, .rightForearm: return "hand.raised.palm.facing"
        case .hips: return "figure.mixed.cardio"
        case .leftThigh, .rightThigh: return "figure.walk"
        case .leftCalf, .rightCalf: return "figure.run"
        }
    }

    /// Whether the SF Symbol should be mirrored horizontally for better left/right semantics
    var shouldMirrorSymbol: Bool {
        switch self {
        case .leftBicep, .leftForearm, .leftThigh, .leftCalf:
            return true
        default:
            return false
        }
    }

    // MARK: - Trend Evaluation

    enum TrendOutcome: Equatable, Sendable {
        case positive
        case negative
        case neutral
    }

    /// Default direction when no goal is set: decrease is good for selected metrics.
    var favorsDecreaseWhenNoGoal: Bool {
        switch self {
        case .weight, .bodyFat, .waist, .hips, .bust:
            return true
        default:
            return false
        }
    }

    enum DefaultFavorableDirection: String, Sendable {
        case increase
        case decrease
        case neutral
    }

    var defaultFavorableDirectionWhenNoGoal: DefaultFavorableDirection {
        switch self {
        case .height:
            return .neutral
        default:
            return favorsDecreaseWhenNoGoal ? .decrease : .increase
        }
    }

    func trendOutcome(from start: Double, to end: Double, goal: MetricGoal?) -> TrendOutcome {
        if let goal {
            let startDistance = abs(goal.targetValue - start)
            let endDistance = abs(goal.targetValue - end)
            if endDistance < startDistance { return .positive }
            if endDistance > startDistance { return .negative }
            return .neutral
        }

        let delta = end - start
        if delta == 0 { return .neutral }
        if favorsDecreaseWhenNoGoal {
            return delta < 0 ? .positive : .negative
        }
        return delta > 0 ? .positive : .negative
    }

    // MARK: - Unit System
    
    /// Kategoria jednostek dla metryki - używana do konwersji i formatowania
    enum UnitCategory {
        case weight     // kg (metric) / lb (imperial)
        case length     // cm (metric) / in (imperial)
        case percent    // % (zawsze bez konwersji)
    }

    /// Zwraca kategorię jednostek dla tej metryki
    var unitCategory: UnitCategory {
        switch self {
        case .weight, .leanBodyMass:
            return .weight
        case .bodyFat:
            return .percent
        case .height, .waist, .neck, .shoulders, .bust, .chest,
             .leftBicep, .rightBicep, .leftForearm, .rightForearm,
             .hips, .leftThigh, .rightThigh, .leftCalf, .rightCalf:
            return .length
        }
    }

    /// Zwraca symbol jednostki dla wybranego systemu ("metric" lub "imperial")
    /// - Parameter unitsSystem: "metric" dla kg/cm, "imperial" dla lb/in
    /// - Returns: String z symbolem jednostki
    func unitSymbol(unitsSystem: String) -> String {
        switch unitCategory {
        case .weight:
            return unitsSystem == "imperial" ? "lb" : "kg"
        case .length:
            return unitsSystem == "imperial" ? "in" : "cm"
        case .percent:
            return "%"
        }
    }
    
    /// Zwraca symbol jednostki dla wybranego systemu (Bool version)
    /// - Parameter isMetric: true dla kg/cm, false dla lb/in
    /// - Returns: String z symbolem jednostki
    func unit(isMetric: Bool) -> String {
        unitSymbol(unitsSystem: isMetric ? "metric" : "imperial")
    }

    // MARK: - Unit Conversion
    
    /// Konwertuje wartość z jednostek bazowych (metrycznych) na jednostki wyświetlania
    /// - Parameters:
    ///   - value: Wartość w jednostkach metrycznych (kg, cm, %)
    ///   - unitsSystem: "metric" lub "imperial"
    /// - Returns: Wartość w odpowiednich jednostkach dla wyświetlenia
    func valueForDisplay(fromMetric value: Double, unitsSystem: String) -> Double {
        switch unitCategory {
        case .weight:
            // Baza: kg → imperial: lb (1 kg = 2.20462 lb)
            return unitsSystem == "imperial" ? value / 0.45359237 : value
        case .length:
            // Baza: cm → imperial: in (1 in = 2.54 cm)
            return unitsSystem == "imperial" ? value / 2.54 : value
        case .percent:
            // Procenty zawsze bez konwersji
            return value
        }
    }

    /// Konwertuje wartość wprowadzoną przez użytkownika na jednostki bazowe (metryczne)
    /// - Parameters:
    ///   - value: Wartość wprowadzona w UI (lb/in lub kg/cm)
    ///   - unitsSystem: "metric" lub "imperial"
    /// - Returns: Wartość w jednostkach metrycznych do zapisu w bazie
    func valueToMetric(fromDisplay value: Double, unitsSystem: String) -> Double {
        switch unitCategory {
        case .weight:
            // lb → kg przy imperial
            return unitsSystem == "imperial" ? value * 0.45359237 : value
        case .length:
            // in → cm przy imperial
            return unitsSystem == "imperial" ? value * 2.54 : value
        case .percent:
            // Procenty bez konwersji
            return value
        }
    }

    // MARK: - HealthKit Integration
    
    /// Określa czy metryka może być synchronizowana z HealthKit
    /// - Returns: true dla metryk dostępnych w Health app
    var isHealthSynced: Bool {
        switch self {
        case .weight, .bodyFat, .height, .leanBodyMass, .waist:
            return true
        default:
            return false
        }
    }
}
