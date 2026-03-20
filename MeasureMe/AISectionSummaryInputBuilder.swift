import Foundation
import SwiftData

enum AISectionSummaryInputBuilder {
    static func metricsInput(
        userName: String,
        activeKinds: [MetricKind],
        latestByKind: [MetricKind: MetricSample],
        samplesByKind: [MetricKind: [MetricSample]],
        unitsSystem: String
    ) -> SectionInsightInput? {
        var context: [String] = []
        context.append("Active metrics: \(activeKinds.count)")

        for kind in activeKinds.prefix(8) {
            guard let latest = latestByKind[kind] else { continue }
            let value = formattedMetric(kind: kind, value: latest.value, unitsSystem: unitsSystem)
            let delta7 = (samplesByKind[kind] ?? []).deltaText(days: 7, kind: kind, unitsSystem: unitsSystem) ?? "n/a"
            context.append("\(kind.title): \(value), 7d change: \(delta7)")
        }

        guard context.count > 1 else { return nil }
        return SectionInsightInput(
            sectionID: "measurements.metrics",
            sectionTitle: "Metrics",
            userName: userName.nilIfEmpty,
            contextLines: context
        )
    }

    static func healthInput(
        userName: String,
        userGender: Gender,
        latestWaist: Double?,
        latestHeight: Double?,
        latestWeight: Double?,
        latestHips: Double?,
        latestBodyFat: Double?,
        latestLeanMass: Double?,
        unitsSystem: String
    ) -> SectionInsightInput? {
        var context: [String] = []
        let effectiveHeight = latestHeight

        if let weight = latestWeight {
            context.append("Weight: \(formattedMetric(kind: .weight, value: weight, unitsSystem: unitsSystem))")
        }
        if let waist = latestWaist {
            context.append("Waist: \(formattedMetric(kind: .waist, value: waist, unitsSystem: unitsSystem))")
        }
        if let bodyFat = latestBodyFat {
            context.append(String(format: "Body fat: %.1f%%", bodyFat))
        }
        if let leanMass = latestLeanMass {
            context.append("Lean mass: \(formattedMetric(kind: .leanBodyMass, value: leanMass, unitsSystem: unitsSystem))")
        }
        if let whtr = HealthMetricsCalculator.calculateWHtR(waistCm: latestWaist, heightCm: effectiveHeight) {
            context.append(String(format: "WHtR: %.2f (%@)", whtr.ratio, whtr.category.rawValue))
        }
        if let bmi = HealthMetricsCalculator.calculateBMI(weightKg: latestWeight, heightCm: effectiveHeight, age: nil) {
            context.append(String(format: "BMI: %.1f (%@)", bmi.bmi, bmi.category.rawValue))
        }

        let rfm = HealthMetricsCalculator.calculateRFMWithGenderRequirement(
            waistCm: latestWaist,
            heightCm: effectiveHeight,
            gender: userGender
        )
        if case .value(let value) = rfm {
            context.append(String(format: "RFM: %.1f%% (%@)", value.rfm, value.category.rawValue))
        }

        let whr = HealthMetricsCalculator.calculateWHRWithGenderRequirement(
            waistCm: latestWaist,
            hipsCm: latestHips,
            gender: userGender
        )
        if case .value(let value) = whr {
            context.append(String(format: "WHR: %.2f (%@)", value.ratio, value.category.rawValue))
        }

        guard !context.isEmpty else { return nil }
        return SectionInsightInput(
            sectionID: "measurements.health",
            sectionTitle: "Health indicators",
            userName: userName.nilIfEmpty,
            contextLines: context
        )
    }

    static func physiqueInput(
        userName: String,
        userGender: Gender,
        latestWaist: Double?,
        latestHeight: Double?,
        latestBodyFat: Double?,
        latestShoulders: Double?,
        latestChest: Double?,
        latestBust: Double?,
        latestHips: Double?
    ) -> SectionInsightInput? {
        var context: [String] = []

        if let swr = PhysiqueIndicatorsCalculator.calculateSWR(shouldersCm: latestShoulders, waistCm: latestWaist) {
            context.append(String(format: "SWR: %.2f (%@)", swr.value, swr.category.rawValue))
        }

        let cwr = PhysiqueIndicatorsCalculator.calculateCWR(chestCm: latestChest, waistCm: latestWaist, gender: userGender)
        if case .value(let value) = cwr {
            context.append(String(format: "CWR: %.2f (%@)", value.value, value.category.rawValue))
        }

        let hwr = PhysiqueIndicatorsCalculator.calculateHWR(hipsCm: latestHips, waistCm: latestWaist, gender: userGender)
        if case .value(let value) = hwr {
            context.append(String(format: "HWR: %.2f (%@)", value.value, value.category.rawValue))
        }

        let bwr = PhysiqueIndicatorsCalculator.calculateBWR(
            bustCm: latestBust,
            chestCm: latestChest,
            waistCm: latestWaist,
            gender: userGender
        )
        if case .value(let value) = bwr {
            context.append(String(format: "BWR: %.2f (%@)", value.value, value.category.rawValue))
        }

        let shr = PhysiqueIndicatorsCalculator.calculateSHR(shouldersCm: latestShoulders, hipsCm: latestHips, gender: userGender)
        if case .value(let value) = shr {
            context.append(String(format: "SHR: %.2f (%@)", value.value, value.category.rawValue))
        }

        if let whtrVisual = PhysiqueIndicatorsCalculator.classifyWHtRVisual(waistCm: latestWaist, heightCm: latestHeight) {
            context.append(String(format: "Visual WHtR: %.2f (%@)", whtrVisual.ratio, whtrVisual.category.rawValue))
        }

        let bodyFatVisual = PhysiqueIndicatorsCalculator.classifyBodyFat(percent: latestBodyFat, gender: userGender)
        if case .value(let value) = bodyFatVisual {
            context.append(String(format: "Body fat visual: %.1f%% (%@)", value.percent, value.category.rawValue))
        }

        let rfm = HealthMetricsCalculator.calculateRFMWithGenderRequirement(
            waistCm: latestWaist,
            heightCm: latestHeight,
            gender: userGender
        )
        if case .value(let rfmValue) = rfm {
            let rfmVisual = PhysiqueIndicatorsCalculator.classifyRFM(rfm: rfmValue.rfm, gender: userGender)
            if case .value(let value) = rfmVisual {
                context.append(String(format: "RFM visual: %.1f%% (%@)", value.percent, value.category.rawValue))
            }
        }

        guard !context.isEmpty else { return nil }
        return SectionInsightInput(
            sectionID: "measurements.physique",
            sectionTitle: "Physique indicators",
            userName: userName.nilIfEmpty,
            contextLines: context
        )
    }

    static func homeCombinedInput(
        userName: String,
        metricsInput: SectionInsightInput?,
        healthInput: SectionInsightInput?,
        physiqueInput: SectionInsightInput?
    ) -> SectionInsightInput? {
        var context: [String] = []

        if let metricsInput {
            context.append("Metrics section:")
            context.append(contentsOf: metricsInput.contextLines)
        }
        if let healthInput {
            context.append("Health indicators section:")
            context.append(contentsOf: healthInput.contextLines)
        }
        if let physiqueInput {
            context.append("Physique indicators section:")
            context.append(contentsOf: physiqueInput.contextLines)
        }

        guard !context.isEmpty else { return nil }
        return SectionInsightInput(
            sectionID: "home.bottom.summary",
            sectionTitle: "Home summary",
            userName: userName.nilIfEmpty,
            contextLines: context
        )
    }

    private static func formattedMetric(kind: MetricKind, value: Double, unitsSystem: String) -> String {
        let display = kind.valueForDisplay(fromMetric: value, unitsSystem: unitsSystem)
        let unit = kind.unitSymbol(unitsSystem: unitsSystem)
        return String(format: "%.1f %@", display, unit)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
