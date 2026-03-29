// MetricKind.swift
//
// **MetricKind**
// Main enum defining all metric types in the app.
//
// **Responsibilities:**
// - Definition of all available metrics
// - Providing metadata (title, icon, units)
// - Unit conversion metric ↔ imperial
// - Metric classification (weight, length, percent)
//
// **Metric categories:**
// - Body Composition: weight, bodyFat, leanBodyMass
// - Body Size: height, waist
// - Upper Body: neck, shoulders, bust, chest
// - Arms: biceps, forearms (left & right)
// - Lower Body: hips, thighs, calves (left & right)
//
import Foundation
import SwiftUI

enum MetricKind: String, CaseIterable, Hashable, Identifiable, Sendable {
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
    
    /// Human-readable metric name for UI
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

    /// Measurement context for AI prompts — avoids confusing body circumferences with height
    var insightMeasurementContext: String {
        switch self {
        case .weight: return "body weight"
        case .bodyFat: return "body fat percentage"
        case .height: return "height (linear, vertical)"
        case .leanBodyMass: return "lean body mass"
        case .waist, .neck, .shoulders, .bust, .chest,
             .leftBicep, .rightBicep, .leftForearm, .rightForearm,
             .hips, .leftThigh, .rightThigh, .leftCalf, .rightCalf:
            return "body circumference"
        }
    }

    /// English title for AI prompts and internal logic
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

    /// SF Symbols icon name for the metric
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

    /// Whether the icon should be horizontally mirrored.
    /// Bicep and calf: icon defaults to showing right side → right=original, left=mirror.
    /// Forearm: icon defaults to showing left side → left=original, right=mirror.
    /// Thigh: no mirroring — left/right crop handles left/right semantics on its own.
    var shouldMirrorSymbol: Bool {
        switch self {
        case .leftBicep, .rightCalf: return true  // bicep: left mirroruje; calf: right mirroruje
        case .rightForearm:         return true  // forearm: right mirroruje
        default:                    return false
        }
    }

    /// Custom image asset name (Icons8) or nil — then use systemImage
    var customImageName: String? {
        switch self {
        case .weight:                       return "icons8.scale"
        case .bodyFat:                      return "icons8.weightCare"
        case .leanBodyMass:                 return "icons8.fit"
        case .waist:                        return "icons8.femaleBack"
        case .neck:                         return "icons8.neck"
        case .shoulders:                    return "icons8.shoulders"
        case .bust:                         return "icons8.bra"
        case .chest:                        return "icons8.torso"
        case .leftBicep, .rightBicep:       return "icons8.muscle"
        case .leftForearm, .rightForearm:   return "icons8.forearm"
        case .hips:                         return "icons8.womanHips"
        case .leftThigh:                    return "icons8.leftThigh"
        case .rightThigh:                   return "icons8.rightThigh"
        case .leftCalf, .rightCalf:         return "icons8.leg"
        default:                            return nil
        }
    }

    // MARK: - Icon View Builder

    /// Returns the metric icon — custom PNG (Icons8) if available, otherwise SF Symbol.
    /// - `font`:  applied only for SF Symbol fallback
    /// - `size`:  icon size in points
    /// - `tint`:  icon color; for PNG uses renderingMode(.template) + foregroundStyle
    @ViewBuilder
    func iconView(font: Font? = nil, size: CGFloat? = nil, tint: Color? = nil) -> some View {
        if let name = customImageName {
            let s = size ?? 20
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(tint ?? .primary)
                .frame(width: s, height: s)
                .scaleEffect(x: shouldMirrorSymbol ? -1 : 1, y: 1)
        } else {
            Image(systemName: systemImage)
                .font(font ?? .body)
                .scaleEffect(x: shouldMirrorSymbol ? -1 : 1, y: 1)
        }
    }

    // MARK: - Trend Evaluation

    enum TrendOutcome: Equatable, Sendable {
        case positive
        case negative
        case neutral
    }

    /// Default direction when no goal is set: for selected metrics a decrease is favorable.
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

    /// Whether the metric uses "gained/lost" (weight, percent) instead of "increased/decreased" (length).
    var usesGainedLostVerb: Bool {
        unitCategory == .weight || unitCategory == .percent
    }

    // MARK: - Unit System
    
    /// Unit category for the metric — used for conversion and formatting
    enum UnitCategory {
        case weight     // kg (metric) / lb (imperial)
        case length     // cm (metric) / in (imperial)
        case percent    // % (always without conversion)
    }

    /// Returns the unit category for this metric
    nonisolated var unitCategory: UnitCategory {
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

    /// Returns the unit symbol for the selected system ("metric" or "imperial")
    /// - Parameter unitsSystem: "metric" for kg/cm, "imperial" for lb/in
    /// - Returns: String with the unit symbol
    nonisolated func unitSymbol(unitsSystem: String) -> String {
        switch unitCategory {
        case .weight:
            return unitsSystem == "imperial" ? "lb" : "kg"
        case .length:
            return unitsSystem == "imperial" ? "in" : "cm"
        case .percent:
            return "%"
        }
    }
    
    /// Returns the unit symbol for the selected system (Bool version)
    /// - Parameter isMetric: true for kg/cm, false for lb/in
    /// - Returns: String with the unit symbol
    nonisolated func unit(isMetric: Bool) -> String {
        unitSymbol(unitsSystem: isMetric ? "metric" : "imperial")
    }

    // MARK: - Unit Conversion
    
    /// Converts a value from base (metric) units to display units
    /// - Parameters:
    ///   - value: Value in metric units (kg, cm, %)
    ///   - unitsSystem: "metric" or "imperial"
    /// - Returns: Value in the appropriate units for display
    nonisolated func valueForDisplay(fromMetric value: Double, unitsSystem: String) -> Double {
        switch unitCategory {
        case .weight:
            // Base: kg → imperial: lb (1 kg = 2.20462 lb)
            return unitsSystem == "imperial" ? value / 0.45359237 : value
        case .length:
            // Base: cm → imperial: in (1 in = 2.54 cm)
            return unitsSystem == "imperial" ? value / 2.54 : value
        case .percent:
            // Percentages always without conversion
            return value
        }
    }

    nonisolated func formattedDisplayValue(
        _ displayValue: Double,
        unitsSystem: String,
        includeUnit: Bool = true,
        alwaysShowSign: Bool = false
    ) -> String {
        let valueFormat = alwaysShowSign ? "%+.1f" : "%.1f"

        switch unitCategory {
        case .percent:
            return includeUnit
                ? String(format: "\(valueFormat)%%", displayValue)
                : String(format: valueFormat, displayValue)
        case .weight, .length:
            if includeUnit {
                return String(format: "\(valueFormat) %@", displayValue, unitSymbol(unitsSystem: unitsSystem))
            }
            return String(format: valueFormat, displayValue)
        }
    }

    nonisolated func formattedMetricValue(
        fromMetric metricValue: Double,
        unitsSystem: String,
        includeUnit: Bool = true,
        alwaysShowSign: Bool = false
    ) -> String {
        formattedDisplayValue(
            valueForDisplay(fromMetric: metricValue, unitsSystem: unitsSystem),
            unitsSystem: unitsSystem,
            includeUnit: includeUnit,
            alwaysShowSign: alwaysShowSign
        )
    }

    /// Converts a user-entered value to base (metric) units
    /// - Parameters:
    ///   - value: Value entered in the UI (lb/in or kg/cm)
    ///   - unitsSystem: "metric" or "imperial"
    /// - Returns: Value in metric units for storage in the database
    func valueToMetric(fromDisplay value: Double, unitsSystem: String) -> Double {
        switch unitCategory {
        case .weight:
            // lb → kg for imperial
            return unitsSystem == "imperial" ? value * 0.45359237 : value
        case .length:
            // in → cm for imperial
            return unitsSystem == "imperial" ? value * 2.54 : value
        case .percent:
            // Percentages without conversion
            return value
        }
    }

    // MARK: - HealthKit Integration
    
    /// Determines whether the metric can be synced with HealthKit
    /// - Returns: true for metrics available in the Health app
    var isHealthSynced: Bool {
        switch self {
        case .weight, .bodyFat, .height, .leanBodyMass, .waist:
            return true
        default:
            return false
        }
    }
}
