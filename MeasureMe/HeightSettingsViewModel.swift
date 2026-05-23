import SwiftUI
import SwiftData

@Observable @MainActor final class HeightSettingsViewModel {
    var samples: [MetricSample] = []

    var latestTrackedHeight: MetricSample? {
        samples.first { $0.kindRaw == MetricKind.height.rawValue }
    }
}
