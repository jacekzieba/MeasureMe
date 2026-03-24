import HealthKit

/// Handles HealthKit authorization and writing for the 5 synced metrics on watchOS.
final class WatchHealthKitWriter {
    static let shared = WatchHealthKitWriter()

    private let store = HKHealthStore()
    private var isAuthorized = false

    private init() {}

    // MARK: - Authorization

    func requestAuthorizationIfNeeded() async {
        guard HKHealthStore.isHealthDataAvailable(), !isAuthorized else { return }

        let types = shareTypes
        let readTypes = Set(types.map { $0 as HKObjectType })

        do {
            try await store.requestAuthorization(toShare: types, read: readTypes)
            isAuthorized = true
        } catch {
            // Best effort — user may deny
        }
    }

    private var shareTypes: Set<HKSampleType> {
        Set([
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.height),
            HKQuantityType(.leanBodyMass),
            HKQuantityType(.waistCircumference)
        ])
    }

    // MARK: - Save

    func save(kind: WatchMetricKind, metricValue: Double, date: Date) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        await requestAuthorizationIfNeeded()

        guard let (typeId, unit) = healthKitMapping(for: kind) else { return }

        let quantity = HKQuantity(unit: unit, doubleValue: metricValue)
        let sample = HKQuantitySample(
            type: HKQuantityType(typeId),
            quantity: quantity,
            start: date,
            end: date
        )
        try await store.save(sample)
    }

    private func healthKitMapping(for kind: WatchMetricKind) -> (HKQuantityTypeIdentifier, HKUnit)? {
        switch kind {
        case .weight:       return (.bodyMass, .gramUnit(with: .kilo))
        case .bodyFat:      return (.bodyFatPercentage, .percent())
        case .height:       return (.height, .meterUnit(with: .centi))
        case .leanBodyMass: return (.leanBodyMass, .gramUnit(with: .kilo))
        case .waist:        return (.waistCircumference, .meterUnit(with: .centi))
        default:            return nil
        }
    }
}
