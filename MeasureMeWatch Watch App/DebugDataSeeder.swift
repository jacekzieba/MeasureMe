import Foundation
import WidgetKit

#if targetEnvironment(simulator)
/// Seeds fake metric data into App Group UserDefaults for simulator testing.
enum DebugDataSeeder {
    static func seedIfNeeded() {
        guard let defaults = UserDefaults(suiteName: watchAppGroupID) else { return }
        // Only seed once
        guard defaults.data(forKey: "widget_data_weight") == nil else { return }

        let now = Date()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970

        seedMetric(defaults: defaults, encoder: encoder, kind: "weight", now: now,
                   baseValue: 82.0, variance: 1.5, unit: "metric", goalTarget: 78.0, goalDirection: "decrease")
        seedMetric(defaults: defaults, encoder: encoder, kind: "bodyFat", now: now,
                   baseValue: 18.5, variance: 0.8, unit: "metric", goalTarget: 15.0, goalDirection: "decrease")
        seedMetric(defaults: defaults, encoder: encoder, kind: "waist", now: now,
                   baseValue: 84.0, variance: 1.0, unit: "metric", goalTarget: 80.0, goalDirection: "decrease")

        WidgetCenter.shared.reloadTimelines(ofKind: "MeasureMeComplication")
    }

    private static func seedMetric(
        defaults: UserDefaults, encoder: JSONEncoder,
        kind: String, now: Date,
        baseValue: Double, variance: Double, unit: String,
        goalTarget: Double?, goalDirection: String?
    ) {
        var samples: [[String: Any]] = []
        for day in (0..<90).reversed() {
            let date = now.addingTimeInterval(-Double(day) * 24 * 3600)
            let trend = -Double(90 - day) * 0.01 // slight downward trend
            let noise = Double.random(in: -variance...variance) * 0.3
            let value = baseValue + trend + noise
            samples.append([
                "value": round(value * 10) / 10,
                "date": date.timeIntervalSince1970
            ])
        }

        var payload: [String: Any] = [
            "kind": kind,
            "samples": samples,
            "unitsSystem": unit
        ]

        if let target = goalTarget, let direction = goalDirection {
            payload["goal"] = [
                "targetValue": target,
                "startValue": baseValue,
                "direction": direction
            ]
        }

        // Encode using Codable for compatibility with WatchMetricData decoder
        let codableSamples = samples.map { dict in
            SeedSample(value: dict["value"] as! Double, date: Date(timeIntervalSince1970: dict["date"] as! Double))
        }
        var goal: SeedGoal?
        if let target = goalTarget {
            goal = SeedGoal(targetValue: target, startValue: baseValue, direction: goalDirection ?? "decrease")
        }
        let data = SeedData(kind: kind, samples: codableSamples, goal: goal, unitsSystem: unit)
        if let encoded = try? encoder.encode(data) {
            defaults.set(encoded, forKey: "widget_data_\(kind)")
        }
    }
}

private struct SeedSample: Codable { let value: Double; let date: Date }
private struct SeedGoal: Codable { let targetValue: Double; let startValue: Double?; let direction: String }
private struct SeedData: Codable {
    let kind: String; let samples: [SeedSample]; let goal: SeedGoal?; let unitsSystem: String
}
#endif
