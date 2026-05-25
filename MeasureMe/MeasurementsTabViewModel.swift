import Foundation
import SwiftUI

// MARK: - MeasurementsTabViewModel

@MainActor
final class MeasurementsTabViewModel: ObservableObject {

    // MARK: - Sample cache

    @Published var cachedSamplesByKind: [MetricKind: [MetricSample]] = [:]
    @Published var cachedLatestByKind: [MetricKind: MetricSample] = [:]
    @Published var cachedCustomSamples: [String: [MetricSample]] = [:]
    @Published var cachedCustomLatest: [String: MetricSample] = [:]

    // MARK: - Refresh

    @Published var refreshToken = UUID()
}
