import SwiftUI
import SwiftData

@Observable @MainActor final class ProfileStatsViewModel {
    var allSamples: [MetricSample] = []

    var totalLogs: Int {
        if let firstDate = StreakManager.shared.firstActiveDate {
            return allSamples.filter { $0.date >= firstDate }.count
        }
        return allSamples.count
    }

    var motivationalPhrase: String {
        switch totalLogs {
        case 0:
            return AppLocalization.string("profile.stats.phrase.0")
        case 1...10:
            return AppLocalization.string("profile.stats.phrase.1")
        case 11...50:
            return AppLocalization.string("profile.stats.phrase.2")
        case 51...100:
            return AppLocalization.string("profile.stats.phrase.3")
        case 101...250:
            return AppLocalization.string("profile.stats.phrase.4")
        case 251...500:
            return AppLocalization.string("profile.stats.phrase.5")
        case 501...1000:
            return AppLocalization.string("profile.stats.phrase.6")
        default:
            return AppLocalization.string("profile.stats.phrase.7")
        }
    }
}
