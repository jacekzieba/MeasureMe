// MetricChangeRow.swift
//
// **MetricChangeRow**
// One row of a before/after "what changed" list: label, old → new value, and the delta with
// direction and percentage.
//
// **Responsibilities:**
// - Shared renderer for the photo comparison screen and the 3D body model screen, which both
//   present the same shape of per-metric delta underneath a visual (photos, mannequin). On the
//   body model screen the mannequin's geometry is invisible to VoiceOver, so this list is the
//   only way that information reaches someone who can't see it.
// - Takes a display title string rather than a `MetricKind`. The photo comparison always has a
//   `MetricKind` and supplies its `title`, but the body model's paired measurements (bicep,
//   forearm, thigh, calf) are averaged across left and right before they ever reach this row —
//   labelling one "left thigh" would assert a side the model never observed. The body model
//   instead carries a localization key (`BodyMetricChange`), resolved to a title here.
// - Converts stored (metric) values to the user's preferred display units using a
//   `MetricKind.UnitCategory` rather than a full `MetricKind`, since that's all either caller can
//   offer. The conversion factors below mirror `MetricKind`'s own (`unitSymbol`, `valueForDisplay`),
//   which likewise switch only on unit category.
//
import SwiftUI

struct MetricChangeRow: View {
    let title: String
    let oldValue: Double
    let newValue: Double
    let unitCategory: MetricKind.UnitCategory
    let storedUnit: String
    let isGoodIncrease: Bool

    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"

    init(
        title: String,
        oldValue: Double,
        newValue: Double,
        unitCategory: MetricKind.UnitCategory,
        storedUnit: String,
        isGoodIncrease: Bool = false
    ) {
        self.title = title
        self.oldValue = oldValue
        self.newValue = newValue
        self.unitCategory = unitCategory
        self.storedUnit = storedUnit
        self.isGoodIncrease = isGoodIncrease
    }

    /// Convenience initialiser for the photo-comparison screen, which already has a `MetricKind`.
    init(change: MetricChange) {
        self.init(
            title: change.kind.title,
            oldValue: change.oldValue,
            newValue: change.newValue,
            unitCategory: change.kind.unitCategory,
            storedUnit: change.storedUnit,
            isGoodIncrease: change.kind == .leanBodyMass
        )
    }

    /// Convenience initialiser for the body model screen. `BodyMetricChange` values are always
    /// stored in canonical metric units, so `storedUnit` is the category's own metric symbol.
    init(change: BodyMetricChange) {
        self.init(
            title: AppLocalization.string(change.titleKey),
            oldValue: change.oldValue,
            newValue: change.newValue,
            unitCategory: change.unitCategory,
            storedUnit: Self.unitSymbol(for: change.unitCategory, unitsSystem: "metric")
        )
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)

                HStack(spacing: 4) {
                    Text("\(displayValue(oldValue).formatted(.number.precision(.fractionLength(1)))) → \(displayValue(newValue).formatted(.number.precision(.fractionLength(1)))) \(displayUnit)")
                        .font(.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                if difference != 0 {
                    Image(systemName: difference > 0 ? "arrow.up" : "arrow.down")
                        .font(.caption)
                        .foregroundStyle(changeColor)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(abs(displayValue(difference)).formatted(.number.precision(.fractionLength(1)))) \(displayUnit)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(changeColor)

                        if let percentageChange {
                            Text("\(abs(percentageChange).formatted(.number.precision(.fractionLength(1))))%")
                                .font(.caption2)
                                .foregroundStyle(AppColorRoles.textSecondary)
                        }
                    }
                } else {
                    Text(AppLocalization.string("No change"))
                        .font(.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                }
            }
        }
    }

    private var difference: Double {
        newValue - oldValue
    }

    private var percentageChange: Double? {
        guard oldValue != 0 else { return nil }
        return (difference / oldValue) * 100
    }

    private var isMetricStored: Bool {
        storedUnit == Self.unitSymbol(for: unitCategory, unitsSystem: "metric")
    }

    private var displayUnit: String {
        isMetricStored ? Self.unitSymbol(for: unitCategory, unitsSystem: unitsSystem) : storedUnit
    }

    private func displayValue(_ value: Double) -> Double {
        isMetricStored ? Self.valueForDisplay(value, category: unitCategory, unitsSystem: unitsSystem) : value
    }

    private var changeColor: Color {
        // For most metrics an increase is unfavourable (red) and a decrease is favourable (green).
        // Exception: metrics where `isGoodIncrease` is set (e.g. lean body mass), where it's reversed.
        if difference > 0 {
            return isGoodIncrease ? AppColorRoles.stateSuccess : AppColorRoles.stateError
        } else if difference < 0 {
            return isGoodIncrease ? AppColorRoles.stateError : AppColorRoles.stateSuccess
        } else {
            return AppColorRoles.textSecondary
        }
    }

    /// Mirrors `MetricKind.unitSymbol(unitsSystem:)`, which itself switches only on unit category.
    private static func unitSymbol(for category: MetricKind.UnitCategory, unitsSystem: String) -> String {
        switch category {
        case .weight:
            return unitsSystem == "imperial" ? "lb" : "kg"
        case .length:
            return unitsSystem == "imperial" ? "in" : "cm"
        case .percent:
            return "%"
        }
    }

    /// Mirrors `MetricKind.valueForDisplay(fromMetric:unitsSystem:)`, which itself switches only
    /// on unit category.
    private static func valueForDisplay(_ value: Double, category: MetricKind.UnitCategory, unitsSystem: String) -> Double {
        switch category {
        case .weight:
            return unitsSystem == "imperial" ? value / 0.45359237 : value
        case .length:
            return unitsSystem == "imperial" ? value / 2.54 : value
        case .percent:
            return value
        }
    }
}
