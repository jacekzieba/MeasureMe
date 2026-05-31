import Foundation
import SwiftUI

// MARK: - MeasurementsTabViewModel

@Observable @MainActor
final class MeasurementsTabViewModel {

    // MARK: - Sample cache

    var cachedSamplesByKind: [MetricKind: [MetricSample]] = [:]
    var cachedLatestByKind: [MetricKind: MetricSample] = [:]
    var cachedCustomSamples: [String: [MetricSample]] = [:]
    var cachedCustomLatest: [String: MetricSample] = [:]

    // MARK: - Refresh

    var refreshToken = UUID()
}
