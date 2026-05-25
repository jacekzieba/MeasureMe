import SwiftUI
import SwiftData

@Observable @MainActor final class TrackedMeasurementsViewModel {
    var customDefinitions: [CustomMetricDefinition] = []
}
