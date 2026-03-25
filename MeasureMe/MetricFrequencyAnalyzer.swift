import Foundation

// MARK: - MetricLoggingPattern

struct MetricLoggingPattern: Codable, Equatable {
    let kindRaw: String
    let dayOfWeek: Int       // 1=Sunday ... 7=Saturday (Calendar convention)
    let hourBucketStart: Int // 0, 3, 6, 9, 12, 15, 18, 21
    let occurrenceCount: Int
    let confidence: Double   // occurrences / totalSamples for this metric
}

// MARK: - MetricAnalysisResult

struct MetricAnalysisResult {
    let lastLogDates: [String: Date]
    let averageIntervals: [String: TimeInterval]
    let patterns: [MetricLoggingPattern]
}

// MARK: - MetricFrequencyAnalyzer

enum MetricFrequencyAnalyzer {

    private static let minSamplesForStaleness = 3
    private static let minSamplesForPattern = 4
    private static let patternWindowDays = 90
    private static let minPatternConfidence = 0.4
    private static let hourBucketSize = 3

    struct Sample {
        let kindRaw: String
        let date: Date
    }

    static func analyze(samples: [Sample], now: Date, calendar: Calendar = .current) -> MetricAnalysisResult {
        let grouped = Dictionary(grouping: samples, by: \.kindRaw)

        var lastLogDates: [String: Date] = [:]
        var averageIntervals: [String: TimeInterval] = [:]
        var patterns: [MetricLoggingPattern] = []

        let windowStart = calendar.date(byAdding: .day, value: -patternWindowDays, to: now) ?? now

        for (kindRaw, kindSamples) in grouped {
            let sorted = kindSamples.sorted { $0.date < $1.date }

            // Last log date
            if let last = sorted.last {
                lastLogDates[kindRaw] = last.date
            }

            // Average interval (needs minSamplesForStaleness)
            if sorted.count >= minSamplesForStaleness {
                let recentSorted = sorted.suffix(minSamplesForStaleness + 5) // use up to 8 most recent
                let dates = Array(recentSorted.map(\.date))
                let interval = computeAverageInterval(dates: dates)
                if interval > 0 {
                    averageIntervals[kindRaw] = interval
                }
            }

            // Pattern detection (needs minSamplesForPattern in window)
            let windowSamples = sorted.filter { $0.date >= windowStart }
            if windowSamples.count >= minSamplesForPattern {
                if let pattern = detectPattern(kindRaw: kindRaw, samples: windowSamples, calendar: calendar) {
                    patterns.append(pattern)
                }
            }
        }

        return MetricAnalysisResult(
            lastLogDates: lastLogDates,
            averageIntervals: averageIntervals,
            patterns: patterns
        )
    }

    // MARK: - Private Helpers

    private static func computeAverageInterval(dates: [Date]) -> TimeInterval {
        guard dates.count >= 2 else { return 0 }
        var totalInterval: TimeInterval = 0
        for i in 1..<dates.count {
            totalInterval += dates[i].timeIntervalSince(dates[i - 1])
        }
        return totalInterval / Double(dates.count - 1)
    }

    private static func detectPattern(
        kindRaw: String,
        samples: [Sample],
        calendar: Calendar
    ) -> MetricLoggingPattern? {
        // Count occurrences per (dayOfWeek, hourBucket)
        var slotCounts: [Int: Int] = [:] // encoded key = dayOfWeek * 100 + hourBucket

        for sample in samples {
            let dow = calendar.component(.weekday, from: sample.date)
            let hour = calendar.component(.hour, from: sample.date)
            let bucket = (hour / hourBucketSize) * hourBucketSize
            let key = dow * 100 + bucket
            slotCounts[key, default: 0] += 1
        }

        // Find the slot with the most occurrences
        guard let (topKey, topCount) = slotCounts.max(by: { $0.value < $1.value }) else {
            return nil
        }

        let confidence = Double(topCount) / Double(samples.count)
        guard topCount >= minSamplesForPattern && confidence >= minPatternConfidence else {
            return nil
        }

        let dayOfWeek = topKey / 100
        let hourBucket = topKey % 100

        return MetricLoggingPattern(
            kindRaw: kindRaw,
            dayOfWeek: dayOfWeek,
            hourBucketStart: hourBucket,
            occurrenceCount: topCount,
            confidence: confidence
        )
    }
}
