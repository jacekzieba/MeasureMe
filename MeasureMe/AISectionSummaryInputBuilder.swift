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
        let recentCheckIns = activeKinds.reduce(into: 0) { partialResult, kind in
            partialResult += samplesByKind[kind].map { samplesInLast($0, days: 30).count } ?? 0
        }
        context.append("Recent check-ins across active metrics (30d): \(recentCheckIns)")

        for kind in activeKinds.prefix(8) {
            guard let latest = latestByKind[kind],
                  let snapshot = trendSnapshot(
                    kind: kind,
                    latest: latest,
                    samples: samplesByKind[kind] ?? [],
                    unitsSystem: unitsSystem
                  ) else { continue }
            context.append(metricContextLine(kind: kind, snapshot: snapshot))
        }

        context.append(contentsOf: metricsSignals(
            activeKinds: activeKinds,
            samplesByKind: samplesByKind,
            unitsSystem: unitsSystem
        ))

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
        samplesByKind: [MetricKind: [MetricSample]],
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
        appendTrendLine(for: .weight, label: "Weight trend", samplesByKind: samplesByKind, unitsSystem: unitsSystem, into: &context)
        appendTrendLine(for: .waist, label: "Waist trend", samplesByKind: samplesByKind, unitsSystem: unitsSystem, into: &context)
        appendTrendLine(for: .bodyFat, label: "Body fat trend", samplesByKind: samplesByKind, unitsSystem: unitsSystem, into: &context)
        appendTrendLine(for: .leanBodyMass, label: "Lean mass trend", samplesByKind: samplesByKind, unitsSystem: unitsSystem, into: &context)

        if let whtr = HealthMetricsCalculator.calculateWHtR(waistCm: latestWaist, heightCm: effectiveHeight) {
            context.append(String(format: "WHtR: %.2f (%@)", whtr.ratio, whtr.category.rawValue))
            if abs(whtr.ratio - 0.50) <= 0.02 || abs(whtr.ratio - 0.60) <= 0.02 {
                context.append(String(format: "WHtR threshold proximity: %.2f is close to a category boundary", whtr.ratio))
            }
        }
        let bmi = HealthMetricsCalculator.calculateBMI(weightKg: latestWeight, heightCm: effectiveHeight, age: nil)
        if let bmi {
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

        context.append(contentsOf: healthSignals(
            latestWeight: latestWeight,
            latestWaist: latestWaist,
            latestBodyFat: latestBodyFat,
            latestLeanMass: latestLeanMass,
            whtr: HealthMetricsCalculator.calculateWHtR(waistCm: latestWaist, heightCm: effectiveHeight),
            bmi: bmi,
            rfm: rfm,
            samplesByKind: samplesByKind,
            unitsSystem: unitsSystem
        ))

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
        latestHips: Double?,
        samplesByKind: [MetricKind: [MetricSample]],
        unitsSystem: String
    ) -> SectionInsightInput? {
        var context: [String] = []

        appendTrendLine(for: .waist, label: "Waist trend", samplesByKind: samplesByKind, unitsSystem: unitsSystem, into: &context)
        appendTrendLine(for: .shoulders, label: "Shoulders trend", samplesByKind: samplesByKind, unitsSystem: unitsSystem, into: &context)
        appendTrendLine(for: .chest, label: "Chest trend", samplesByKind: samplesByKind, unitsSystem: unitsSystem, into: &context)
        appendTrendLine(for: .bust, label: "Bust trend", samplesByKind: samplesByKind, unitsSystem: unitsSystem, into: &context)
        appendTrendLine(for: .hips, label: "Hips trend", samplesByKind: samplesByKind, unitsSystem: unitsSystem, into: &context)
        appendTrendLine(for: .bodyFat, label: "Body fat trend", samplesByKind: samplesByKind, unitsSystem: unitsSystem, into: &context)

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

        context.append(contentsOf: physiqueSignals(
            latestWaist: latestWaist,
            latestShoulders: latestShoulders,
            latestChest: latestChest,
            latestBust: latestBust,
            latestHips: latestHips,
            latestBodyFat: latestBodyFat,
            samplesByKind: samplesByKind,
            unitsSystem: unitsSystem
        ))

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

    private struct TrendSnapshot {
        let latestText: String
        let delta7Text: String?
        let delta30Text: String?
        let recentSampleCount: Int
        let momentumText: String?
    }

    private static func trendSnapshot(
        kind: MetricKind,
        latest: MetricSample,
        samples: [MetricSample],
        unitsSystem: String
    ) -> TrendSnapshot? {
        let delta7 = samples.deltaText(days: 7, kind: kind, unitsSystem: unitsSystem)
        let delta30 = samples.deltaText(days: 30, kind: kind, unitsSystem: unitsSystem)
        let recentCount = samplesInLast(samples, days: 30).count
        let momentum = momentumHint(kind: kind, samples: samples, unitsSystem: unitsSystem)

        return TrendSnapshot(
            latestText: formattedMetric(kind: kind, value: latest.value, unitsSystem: unitsSystem),
            delta7Text: delta7,
            delta30Text: delta30,
            recentSampleCount: recentCount,
            momentumText: momentum
        )
    }

    private static func metricContextLine(kind: MetricKind, snapshot: TrendSnapshot) -> String {
        var parts = [
            "\(kind.englishTitle): \(snapshot.latestText)",
            "30d samples: \(snapshot.recentSampleCount)"
        ]

        if let delta7 = snapshot.delta7Text {
            parts.append("7d change: \(delta7)")
        }
        if let delta30 = snapshot.delta30Text {
            parts.append("30d change: \(delta30)")
        }
        if let momentum = snapshot.momentumText {
            parts.append("pace: \(momentum)")
        }

        return parts.joined(separator: ", ")
    }

    private static func appendTrendLine(
        for kind: MetricKind,
        label: String,
        samplesByKind: [MetricKind: [MetricSample]],
        unitsSystem: String,
        into context: inout [String]
    ) {
        guard let samples = samplesByKind[kind],
              let latest = latestSample(in: samples),
              let snapshot = trendSnapshot(kind: kind, latest: latest, samples: samples, unitsSystem: unitsSystem) else {
            return
        }
        var parts = [
            "\(label): \(snapshot.latestText)",
            "30d samples: \(snapshot.recentSampleCount)"
        ]
        if let delta7 = snapshot.delta7Text {
            parts.append("7d change: \(delta7)")
        }
        if let delta30 = snapshot.delta30Text {
            parts.append("30d change: \(delta30)")
        }
        if let momentum = snapshot.momentumText {
            parts.append("pace: \(momentum)")
        }
        context.append(parts.joined(separator: ", "))
    }

    private static func metricsSignals(
        activeKinds: [MetricKind],
        samplesByKind: [MetricKind: [MetricSample]],
        unitsSystem: String
    ) -> [String] {
        var signals: [String] = []
        let activeSet = Set(activeKinds)

        if activeSet.contains(.weight) || activeSet.contains(.waist) || activeSet.contains(.leanBodyMass) {
            let composition = compositionSignal(samplesByKind: samplesByKind, unitsSystem: unitsSystem)
            if let composition {
                signals.append(composition)
            }
        }

        if activeSet.contains(.shoulders) || activeSet.contains(.chest) || activeSet.contains(.waist) {
            if let upperBody = upperBodySignal(samplesByKind: samplesByKind, unitsSystem: unitsSystem) {
                signals.append(upperBody)
            }
        }

        let slowdownKinds = activeKinds.prefix(8).compactMap { kind -> String? in
            guard let samples = samplesByKind[kind],
                  let hint = momentumHint(kind: kind, samples: samples, unitsSystem: unitsSystem) else {
                return nil
            }
            if hint == "recent move opposes the 30d direction" || hint == "recent pace is softer than the 30d trend" {
                return "\(kind.englishTitle): \(hint)"
            }
            return nil
        }
        if !slowdownKinds.isEmpty {
            signals.append("Momentum signals: \(slowdownKinds.joined(separator: "; "))")
        }

        return signals
    }

    private static func healthSignals(
        latestWeight: Double?,
        latestWaist: Double?,
        latestBodyFat: Double?,
        latestLeanMass: Double?,
        whtr: HealthMetricsCalculator.WHtRResult?,
        bmi: HealthMetricsCalculator.BMIResult?,
        rfm: GenderDependentResult<HealthMetricsCalculator.RFMResult>?,
        samplesByKind: [MetricKind: [MetricSample]],
        unitsSystem: String
    ) -> [String] {
        var signals: [String] = []

        if let composition = compositionSignal(samplesByKind: samplesByKind, unitsSystem: unitsSystem) {
            signals.append(composition)
        }

        if let whtr, let bmi,
           bmi.category == .normal,
           whtr.category != .normal {
            signals.append("Subtle signal: BMI looks normal, but waist-based markers are less favorable than scale weight alone suggests.")
        }

        if case .value(let rfmValue)? = rfm,
           let latestBodyFat,
           abs(rfmValue.rfm - latestBodyFat) >= 4 {
            signals.append(String(format: "Body fat signal: measured body fat and RFM differ by %.1f points, so waist distribution and direct composition readings are telling a slightly different story.", abs(rfmValue.rfm - latestBodyFat)))
        }

        if let latestWeight, let latestWaist, latestWeight > 0, latestWaist > 0,
           let weight30 = deltaValue(for: .weight, days: 30, samplesByKind: samplesByKind, unitsSystem: unitsSystem),
           let waist30 = deltaValue(for: .waist, days: 30, samplesByKind: samplesByKind, unitsSystem: unitsSystem),
           isStable(weight30, for: .weight),
           isMeaningfulDecrease(waist30, for: .waist) {
            signals.append("Body composition signal: scale weight stayed fairly steady while waist moved down, which often reflects progress not obvious on the scale.")
        }

        if let latestLeanMass,
           let latestBodyFat,
           latestLeanMass > 0,
           latestBodyFat > 0,
           let lean30 = deltaValue(for: .leanBodyMass, days: 30, samplesByKind: samplesByKind, unitsSystem: unitsSystem),
           let bodyFat30 = deltaValue(for: .bodyFat, days: 30, samplesByKind: samplesByKind, unitsSystem: unitsSystem),
           !isMeaningfulDecrease(lean30, for: .leanBodyMass),
           isMeaningfulDecrease(bodyFat30, for: .bodyFat) {
            signals.append("Composition signal: body fat is trending down without a matching drop in lean mass, which supports a cleaner body-composition change.")
        }

        return signals
    }

    private static func physiqueSignals(
        latestWaist: Double?,
        latestShoulders: Double?,
        latestChest: Double?,
        latestBust: Double?,
        latestHips: Double?,
        latestBodyFat: Double?,
        samplesByKind: [MetricKind: [MetricSample]],
        unitsSystem: String
    ) -> [String] {
        var signals: [String] = []

        if let shoulders30 = deltaValue(for: .shoulders, days: 30, samplesByKind: samplesByKind, unitsSystem: unitsSystem),
           let waist30 = deltaValue(for: .waist, days: 30, samplesByKind: samplesByKind, unitsSystem: unitsSystem),
           isMeaningfulIncrease(shoulders30, for: .shoulders),
           isMeaningfulDecrease(waist30, for: .waist) {
            signals.append("Shape signal: shoulders are trending up while waist is trending down, which usually sharpens the V-taper look.")
        }

        let chestKind: MetricKind? = latestBust != nil ? .bust : (latestChest != nil ? .chest : nil)
        if let chestKind,
           let chest30 = deltaValue(for: chestKind, days: 30, samplesByKind: samplesByKind, unitsSystem: unitsSystem),
           let waist30 = deltaValue(for: .waist, days: 30, samplesByKind: samplesByKind, unitsSystem: unitsSystem),
           isMeaningfulIncrease(chest30, for: chestKind),
           isMeaningfulDecrease(waist30, for: .waist) {
            signals.append("Proportion signal: upper-body size is improving while waist is tightening, so proportions should look stronger than the scale alone suggests.")
        }

        if let hips30 = deltaValue(for: .hips, days: 30, samplesByKind: samplesByKind, unitsSystem: unitsSystem),
           let waist30 = deltaValue(for: .waist, days: 30, samplesByKind: samplesByKind, unitsSystem: unitsSystem),
           isStable(hips30, for: .hips),
           isMeaningfulDecrease(waist30, for: .waist) {
            signals.append("Silhouette signal: hips are holding fairly steady while waist is dropping, which usually makes shape changes easier to notice visually.")
        }

        if let bodyFat30 = deltaValue(for: .bodyFat, days: 30, samplesByKind: samplesByKind, unitsSystem: unitsSystem),
           isMeaningfulDecrease(bodyFat30, for: .bodyFat),
           latestBodyFat != nil,
           latestWaist != nil,
           latestHips != nil || latestShoulders != nil {
            signals.append("Visual composition signal: body fat is moving down, so small ratio changes may be more visible in the mirror than in a single circumference reading.")
        }

        return signals
    }

    private static func compositionSignal(
        samplesByKind: [MetricKind: [MetricSample]],
        unitsSystem: String
    ) -> String? {
        let weight30 = deltaValue(for: .weight, days: 30, samplesByKind: samplesByKind, unitsSystem: unitsSystem)
        let waist30 = deltaValue(for: .waist, days: 30, samplesByKind: samplesByKind, unitsSystem: unitsSystem)
        let lean30 = deltaValue(for: .leanBodyMass, days: 30, samplesByKind: samplesByKind, unitsSystem: unitsSystem)
        let bodyFat30 = deltaValue(for: .bodyFat, days: 30, samplesByKind: samplesByKind, unitsSystem: unitsSystem)

        if let weight30, let waist30,
           isMeaningfulDecrease(weight30, for: .weight),
           isMeaningfulDecrease(waist30, for: .waist) {
            if let lean30, !isMeaningfulDecrease(lean30, for: .leanBodyMass) {
                return "Cross-metric signal: weight and waist are both down over 30 days while lean mass is holding, which points to solid fat-loss progress."
            }
            return "Cross-metric signal: weight and waist are both down over 30 days, so the trend is aligned rather than random scale noise."
        }

        if let weight30, let waist30,
           isStable(weight30, for: .weight),
           isMeaningfulDecrease(waist30, for: .waist) {
            return "Cross-metric signal: weight is broadly stable while waist is down, which often means body recomposition rather than stalled progress."
        }

        if let weight30, let lean30,
           isMeaningfulDecrease(weight30, for: .weight),
           isMeaningfulDecrease(lean30, for: .leanBodyMass) {
            return "Cross-metric signal: weight and lean mass are both down, so the drop may not be coming only from body fat."
        }

        if let weight30, let bodyFat30,
           isStable(weight30, for: .weight),
           isMeaningfulDecrease(bodyFat30, for: .bodyFat) {
            return "Cross-metric signal: scale weight is steady while body fat is down, which is a useful recomposition pattern."
        }

        return nil
    }

    private static func upperBodySignal(
        samplesByKind: [MetricKind: [MetricSample]],
        unitsSystem: String
    ) -> String? {
        if let shoulders30 = deltaValue(for: .shoulders, days: 30, samplesByKind: samplesByKind, unitsSystem: unitsSystem),
           let waist30 = deltaValue(for: .waist, days: 30, samplesByKind: samplesByKind, unitsSystem: unitsSystem),
           isMeaningfulIncrease(shoulders30, for: .shoulders),
           isStableOrDecrease(waist30, for: .waist) {
            return "Upper-body signal: shoulders are improving without waist growth, which can support a more athletic shape."
        }

        if let chest30 = deltaValue(for: .chest, days: 30, samplesByKind: samplesByKind, unitsSystem: unitsSystem),
           let waist30 = deltaValue(for: .waist, days: 30, samplesByKind: samplesByKind, unitsSystem: unitsSystem),
           isMeaningfulIncrease(chest30, for: .chest),
           isStableOrDecrease(waist30, for: .waist) {
            return "Upper-body signal: chest is trending up while waist is flat or down, which often matches muscle-building progress."
        }

        return nil
    }

    private static func latestSample(in samples: [MetricSample]) -> MetricSample? {
        samples.max(by: { $0.date < $1.date })
    }

    private static func samplesInLast(_ samples: [MetricSample], days: Int, now: Date = AppClock.now) -> [MetricSample] {
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return samples }
        return samples.filter { $0.date >= start }
    }

    private static func deltaValue(
        for kind: MetricKind,
        days: Int,
        samplesByKind: [MetricKind: [MetricSample]],
        unitsSystem: String,
        now: Date = AppClock.now
    ) -> Double? {
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: now),
              let samples = samplesByKind[kind] else { return nil }
        let window = samples.filter { $0.date >= start }
        guard let newest = window.max(by: { $0.date < $1.date }),
              let oldest = window.min(by: { $0.date < $1.date }),
              newest.persistentModelID != oldest.persistentModelID else {
            return nil
        }
        let newestValue = kind.valueForDisplay(fromMetric: newest.value, unitsSystem: unitsSystem)
        let oldestValue = kind.valueForDisplay(fromMetric: oldest.value, unitsSystem: unitsSystem)
        return newestValue - oldestValue
    }

    private static func momentumHint(
        kind: MetricKind,
        samples: [MetricSample],
        unitsSystem: String
    ) -> String? {
        guard let delta7 = deltaValue(for: kind, days: 7, samplesByKind: [kind: samples], unitsSystem: unitsSystem),
              let delta30 = deltaValue(for: kind, days: 30, samplesByKind: [kind: samples], unitsSystem: unitsSystem) else {
            return nil
        }

        if isStable(delta7, for: kind), isStable(delta30, for: kind) {
            return "steady across both 7d and 30d"
        }

        let sameDirection = delta7 == 0 || delta30 == 0 || delta7.sign == delta30.sign
        let pace7 = abs(delta7) / 7
        let pace30 = abs(delta30) / 30

        if !sameDirection, !isStable(delta7, for: kind), !isStable(delta30, for: kind) {
            return "recent move opposes the 30d direction"
        }
        if pace30 == 0 {
            return nil
        }
        if pace7 > pace30 * 1.35 {
            return "recent pace is stronger than the 30d trend"
        }
        if pace7 < pace30 * 0.65 {
            return "recent pace is softer than the 30d trend"
        }
        return "recent pace broadly matches the 30d trend"
    }

    private static func stabilityThreshold(for kind: MetricKind) -> Double {
        switch kind.unitCategory {
        case .percent:
            return 0.4
        case .weight:
            return 0.6
        case .length:
            return 0.8
        }
    }

    private static func meaningfulThreshold(for kind: MetricKind) -> Double {
        switch kind.unitCategory {
        case .percent:
            return 0.6
        case .weight:
            return 0.8
        case .length:
            return 1.0
        }
    }

    private static func isStable(_ delta: Double, for kind: MetricKind) -> Bool {
        abs(delta) < stabilityThreshold(for: kind)
    }

    private static func isMeaningfulIncrease(_ delta: Double, for kind: MetricKind) -> Bool {
        delta >= meaningfulThreshold(for: kind)
    }

    private static func isMeaningfulDecrease(_ delta: Double, for kind: MetricKind) -> Bool {
        delta <= -meaningfulThreshold(for: kind)
    }

    private static func isStableOrDecrease(_ delta: Double, for kind: MetricKind) -> Bool {
        isStable(delta, for: kind) || isMeaningfulDecrease(delta, for: kind)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
