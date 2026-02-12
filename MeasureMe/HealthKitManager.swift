//
// HealthKitManager.swift
//
// Menedżer odpowiedzialny za autoryzację i operacje na danych HealthKit
// (wzrost, masa ciała, procent tkanki tłuszczowej, beztłuszczowa masa ciała, obwód talii).
//
// Zrefaktoryzowano do wzorca z wstrzykiwanym "store" (protocol HealthStore),
// aby umożliwić testy jednostkowe bez prawdziwego HKHealthStore.
//

import Foundation
import HealthKit
import SwiftData

// MARK: - Abstrakcja nad HKHealthStore (do testów)

protocol HealthStore {
    func isHealthDataAvailable() -> Bool
    func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws

    // Quantity helpers
    func latestQuantity(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> (value: Double, date: Date)?
    func anchoredQuantitySamples(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        anchorData: Data?,
        since: Date?
    ) async throws -> (
        samples: [(value: Double, date: Date, sourceBundleID: String?)],
        newAnchorData: Data?
    )
    func saveQuantity(_ value: Double, unit: HKUnit, identifier: HKQuantityTypeIdentifier, date: Date) async throws

    // Waist helpers
    func fetchWaistMeasurements() async throws -> [(value: Double, date: Date)]
    func saveWaistMeasurement(value: Double, date: Date) async throws
    func deleteWaistMeasurements(inDay date: Date) async throws
}

// MARK: - Implementacja produkcyjna oparta o HKHealthStore

final class RealHealthStore: HealthStore {
    let store = HKHealthStore()  // Zmieniono na 'let' zamiast 'private let'

    private enum HealthStoreError: LocalizedError {
        case deleteFailed

        var errorDescription: String? {
            AppLocalization.string("Failed to delete HealthKit samples.")
        }
    }

    func isHealthDataAvailable() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws {
        try await store.requestAuthorization(toShare: toShare, read: read)
    }

    func latestQuantity(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> (value: Double, date: Date)? {
        let type = HKQuantityType.quantityType(forIdentifier: identifier)!

        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    return continuation.resume(throwing: error)
                }
                guard let sample = (samples as? [HKQuantitySample])?.first else {
                    return continuation.resume(returning: nil)
                }
                let value = sample.quantity.doubleValue(for: unit)
                continuation.resume(returning: (value: value, date: sample.startDate))
            }
            self.store.execute(query)
        }
    }

    func anchoredQuantitySamples(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        anchorData: Data?,
        since: Date?
    ) async throws -> (
        samples: [(value: Double, date: Date, sourceBundleID: String?)],
        newAnchorData: Data?
    ) {
        let type = HKQuantityType.quantityType(forIdentifier: identifier)!
        let predicate: NSPredicate?
        if let since {
            // Strictly newer than last processed point to avoid duplicate imports.
            predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate)
        } else {
            predicate = nil
        }
        let anchor = anchorData.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit,
                resultsHandler: { _, samples, _, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let mapped = (samples as? [HKQuantitySample])?.map { sample in
                    (
                        value: sample.quantity.doubleValue(for: unit),
                        date: sample.startDate,
                        sourceBundleID: sample.sourceRevision.source.bundleIdentifier
                    )
                } ?? []
                let newAnchorData = newAnchor.flatMap {
                    try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
                }

                continuation.resume(returning: (samples: mapped, newAnchorData: newAnchorData))
            }
            )
            self.store.execute(query)
        }
    }

    func saveQuantity(_ value: Double, unit: HKUnit, identifier: HKQuantityTypeIdentifier, date: Date) async throws {
        let type = HKQuantityType.quantityType(forIdentifier: identifier)!
        let quantity = HKQuantity(unit: unit, doubleValue: value)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
        try await store.save(sample)
    }

    func fetchWaistMeasurements() async throws -> [(value: Double, date: Date)] {
        let waistType = HKQuantityType.quantityType(forIdentifier: .waistCircumference)!
        let predicate = HKQuery.predicateForSamples(withStart: .distantPast, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: waistType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let results = (samples as? [HKQuantitySample])?.map {
                    (
                        value: $0.quantity.doubleValue(for: .meterUnit(with: .centi)),
                        date: $0.startDate
                    )
                } ?? []
                continuation.resume(returning: results)
            }
            self.store.execute(query)
        }
    }

    func saveWaistMeasurement(value: Double, date: Date) async throws {
        let waistType = HKQuantityType.quantityType(forIdentifier: .waistCircumference)!
        let quantity = HKQuantity(unit: .meterUnit(with: .centi), doubleValue: value)
        let sample = HKQuantitySample(type: waistType, quantity: quantity, start: date, end: date)
        try await store.save(sample)
    }

    func deleteWaistMeasurements(inDay date: Date) async throws {
        let waistType = HKQuantityType.quantityType(forIdentifier: .waistCircumference)!
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let samplesToDelete: [HKObject] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: waistType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }

        guard !samplesToDelete.isEmpty else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.delete(samplesToDelete) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard success else {
                    continuation.resume(throwing: HealthStoreError.deleteFailed)
                    return
                }
                continuation.resume(returning: ())
            }
        }
    }
}

// MARK: - HealthKitManager (z możliwością wstrzyknięcia store)

final class HealthKitManager {

    static let shared = HealthKitManager()

    private struct NormalizedImportSample {
        let date: Date
        let value: Double
        let sourceBundleID: String?
    }

    private struct ImportDeduplicationConfig {
        let dateTolerance: TimeInterval
        let valueTolerance: Double
    }

    private struct ImportComparisonSample {
        let date: Date
        let value: Double
    }

    private let store: HealthStore
    private let quantityCacheTTL: TimeInterval = 60 * 30
    private var latestQuantityCache: [HKQuantityTypeIdentifier: (value: Double, date: Date)] = [:]
    private var latestQuantityFetchDate: [HKQuantityTypeIdentifier: Date] = [:]
    private let waistCacheTTL: TimeInterval = 60 * 30
    private var cachedWaistMeasurements: [(value: Double, date: Date)]?
    private var lastWaistFetch: Date?
    private var modelContainer: ModelContainer?
    private var observerQueries: [HKObserverQuery] = []
    private let anchorDataPrefix = "healthkit_anchor_"
    private let processedDatePrefix = "healthkit_last_processed_"
    private let initialHistoricalImportKey = "healthkit_initial_historical_import_v1"
    private let appBundleID = Bundle.main.bundleIdentifier
    private let initialHistoricalKinds: Set<MetricKind> = [.weight, .bodyFat, .leanBodyMass, .waist]
    private let importDateTolerance: TimeInterval = 60

    // Produkcyjny init
    convenience init() {
        self.init(store: RealHealthStore())
    }

    // Init do testów/iniekcji
    init(store: HealthStore) {
        self.store = store
    }

    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Permissions

    func requestAuthorization() async throws {
        guard store.isHealthDataAvailable() else { return }

        let waistType = HKQuantityType.quantityType(forIdentifier: .waistCircumference)!
        let bmiType = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex)!
        let heightType = HKQuantityType.quantityType(forIdentifier: .height)!
        let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        let bodyFatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage)!
        let leanBodyMassType = HKQuantityType.quantityType(forIdentifier: .leanBodyMass)!
        let dateOfBirthType = HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!

        try await store.requestAuthorization(
            toShare: [waistType, bmiType, heightType, weightType, bodyFatType, leanBodyMassType],
            read: [waistType, bmiType, heightType, weightType, bodyFatType, leanBodyMassType, dateOfBirthType]
        )

        startObservingHealthKitUpdates()
        Task(priority: .utility) { [weak self] in
            await self?.importHistoricalDataIfNeeded()
        }
    }

    func startObservingHealthKitUpdates() {
        guard let realStore = store as? RealHealthStore else { return }
        observerQueries.forEach { realStore.store.stop($0) }
        observerQueries.removeAll()
        let initialImportCompleted = UserDefaults.standard.bool(forKey: initialHistoricalImportKey)

        for (identifier, kind, unit, isPercent01) in syncTypes {
            if !UserDefaults.standard.bool(forKey: "healthkit_sync_\(kind.rawValue)") {
                continue
            }
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { continue }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                defer { completion() }
                guard error == nil else { return }
                Task { await self?.importNewQuantities(identifier: identifier, kind: kind, unit: unit, percent01: isPercent01) }
            }
            realStore.store.execute(query)
            observerQueries.append(query)
            realStore.store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }

            // Catch up immediately in case updates happened while observer wasn't active.
            if initialImportCompleted {
                Task(priority: .utility) {
                    await self.importNewQuantities(identifier: identifier, kind: kind, unit: unit, percent01: isPercent01)
                }
            }
        }
    }

    private var syncTypes: [(HKQuantityTypeIdentifier, MetricKind, HKUnit, Bool)] {
        [
            (.bodyMass, .weight, .gramUnit(with: .kilo), false),
            (.bodyFatPercentage, .bodyFat, .percent(), true),
            (.height, .height, .meterUnit(with: .centi), false),
            (.leanBodyMass, .leanBodyMass, .gramUnit(with: .kilo), false),
            (.waistCircumference, .waist, .meterUnit(with: .centi), false)
        ]
    }

    private func importHistoricalDataIfNeeded() async {
        guard let container = modelContainer else { return }
        guard !UserDefaults.standard.bool(forKey: initialHistoricalImportKey) else { return }
        let context = ModelContext(container)
        context.autosaveEnabled = false

        var hadFailure = false
        for (identifier, kind, unit, isPercent01) in syncTypes where initialHistoricalKinds.contains(kind) {
            guard UserDefaults.standard.bool(forKey: "healthkit_sync_\(kind.rawValue)") else { continue }
            do {
                try await importAllHistoricalSamples(
                    identifier: identifier,
                    kind: kind,
                    unit: unit,
                    percent01: isPercent01,
                    context: context
                )
            } catch {
                hadFailure = true
                AppLog.debug("⚠️ Initial historical import failed for \(kind.rawValue): \(error)")
            }
        }

        if !hadFailure {
            UserDefaults.standard.set(true, forKey: initialHistoricalImportKey)
            startObservingHealthKitUpdates()
        }
    }

    private func importAllHistoricalSamples(
        identifier: HKQuantityTypeIdentifier,
        kind: MetricKind,
        unit: HKUnit,
        percent01: Bool,
        context: ModelContext
    ) async throws {
        let anchored = try await store.anchoredQuantitySamples(
            for: identifier,
            unit: unit,
            anchorData: nil,
            since: nil
        )

        guard !anchored.samples.isEmpty || anchored.newAnchorData != nil else { return }
        let importResult = try importSamples(
            anchored.samples,
            for: kind,
            percent01: percent01,
            context: context,
            notifyExternalImports: false
        )

        if importResult.didInsertAny {
            try context.save()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "healthkit_last_import")
        }

        if let newAnchorData = anchored.newAnchorData {
            setStoredAnchorData(newAnchorData, for: kind)
        }
        if let newestDate = importResult.newestDate {
            setLastProcessedDate(newestDate, for: kind)
        }
    }
    
    // MARK: - Date of Birth / Age
    
    /// Pobiera datę urodzenia z HealthKit
    func fetchDateOfBirth() throws -> Date? {
        guard let hkStore = (store as? RealHealthStore)?.store else { return nil }
        
        do {
            let dateComponents = try hkStore.dateOfBirthComponents()
            return Calendar.current.date(from: dateComponents)
        } catch {
            return nil
        }
    }
    
    /// Oblicza wiek na podstawie daty urodzenia
    static func calculateAge(from birthDate: Date) -> Int? {
        let now = Date()
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: birthDate, to: now)
        return ageComponents.year
    }

    // MARK: - Additional metrics (BMI, height, weight, body fat %, lean body mass)

    func fetchLatestBMI() async throws -> (value: Double, date: Date)? {
        try await store.latestQuantity(for: .bodyMassIndex, unit: .count())
    }

    func saveBMI(value: Double, date: Date) async throws {
        try await store.saveQuantity(value, unit: .count(), identifier: .bodyMassIndex, date: date)
    }

    // Height (centimeters)
    func fetchLatestHeightInCentimeters() async throws -> (value: Double, date: Date)? {
        try await store.latestQuantity(for: .height, unit: .meterUnit(with: .centi))
    }

    func saveHeight(centimeters: Double, date: Date) async throws {
        try await store.saveQuantity(centimeters, unit: .meterUnit(with: .centi), identifier: .height, date: date)
    }

    // Weight (kilograms)
    func fetchLatestWeightInKilograms() async throws -> (value: Double, date: Date)? {
        try await store.latestQuantity(for: .bodyMass, unit: .gramUnit(with: .kilo))
    }

    func saveWeight(kilograms: Double, date: Date) async throws {
        try await store.saveQuantity(kilograms, unit: .gramUnit(with: .kilo), identifier: .bodyMass, date: date)
    }

    // Body fat percentage (0.0 - 100.0)
    func fetchLatestBodyFatPercentage() async throws -> (value: Double, date: Date)? {
        if let result = try await store.latestQuantity(for: .bodyFatPercentage, unit: .percent()) {
            // HealthKit przechowuje procent jako 0.0–1.0; konwertujemy na 0–100 do UI.
            return (value: result.value * 100.0, date: result.date)
        }
        return nil
    }

    func saveBodyFatPercentage(percent: Double, date: Date) async throws {
        // Konwersja 0–100 do 0–1
        try await store.saveQuantity(percent / 100.0, unit: .percent(), identifier: .bodyFatPercentage, date: date)
    }

    // Lean body mass (kilograms)
    func fetchLatestLeanBodyMassInKilograms() async throws -> (value: Double, date: Date)? {
        try await store.latestQuantity(for: .leanBodyMass, unit: .gramUnit(with: .kilo))
    }

    func saveLeanBodyMass(kilograms: Double, date: Date) async throws {
        try await store.saveQuantity(kilograms, unit: .gramUnit(with: .kilo), identifier: .leanBodyMass, date: date)
    }
    
    // MARK: - Cached Body Composition Fetch
    
    @MainActor
    func fetchLatestBodyCompositionCached(forceRefresh: Bool = false) async throws -> (bodyFat: Double?, leanMass: Double?) {
        let bodyFat = try await fetchLatestBodyFatPercentageCached(forceRefresh: forceRefresh)?.value
        let leanMass = try await fetchLatestLeanBodyMassInKilogramsCached(forceRefresh: forceRefresh)?.value
        return (bodyFat: bodyFat, leanMass: leanMass)
    }
    
    // MARK: - Cached Quantity Fetches
    
    @MainActor
    func fetchLatestBMICached(forceRefresh: Bool = false) async throws -> (value: Double, date: Date)? {
        try await cachedQuantity(for: .bodyMassIndex, forceRefresh: forceRefresh) {
            try await fetchLatestBMI()
        }
    }
    
    @MainActor
    func fetchLatestHeightInCentimetersCached(forceRefresh: Bool = false) async throws -> (value: Double, date: Date)? {
        try await cachedQuantity(for: .height, forceRefresh: forceRefresh) {
            try await fetchLatestHeightInCentimeters()
        }
    }
    
    @MainActor
    func fetchLatestWeightInKilogramsCached(forceRefresh: Bool = false) async throws -> (value: Double, date: Date)? {
        try await cachedQuantity(for: .bodyMass, forceRefresh: forceRefresh) {
            try await fetchLatestWeightInKilograms()
        }
    }
    
    @MainActor
    func fetchLatestBodyFatPercentageCached(forceRefresh: Bool = false) async throws -> (value: Double, date: Date)? {
        try await cachedQuantity(for: .bodyFatPercentage, forceRefresh: forceRefresh) {
            try await fetchLatestBodyFatPercentage()
        }
    }
    
    @MainActor
    func fetchLatestLeanBodyMassInKilogramsCached(forceRefresh: Bool = false) async throws -> (value: Double, date: Date)? {
        try await cachedQuantity(for: .leanBodyMass, forceRefresh: forceRefresh) {
            try await fetchLatestLeanBodyMassInKilograms()
        }
    }
    
    @MainActor
    private func cachedQuantity(
        for identifier: HKQuantityTypeIdentifier,
        forceRefresh: Bool,
        fetch: () async throws -> (value: Double, date: Date)?
    ) async throws -> (value: Double, date: Date)? {
        let now = Date()
        if !forceRefresh,
           let last = latestQuantityFetchDate[identifier],
           now.timeIntervalSince(last) < quantityCacheTTL,
           let cached = latestQuantityCache[identifier] {
            return cached
        }
        
        let fresh = try await fetch()
        latestQuantityFetchDate[identifier] = now
        if let fresh {
            latestQuantityCache[identifier] = fresh
        } else {
            latestQuantityCache.removeValue(forKey: identifier)
        }
        
        return fresh
    }
    
    // MARK: - Cached Waist Fetch
    
    @MainActor
    func fetchWaistMeasurementsCached(forceRefresh: Bool = false) async throws -> [(value: Double, date: Date)] {
        let now = Date()
        if !forceRefresh,
           let last = lastWaistFetch,
           now.timeIntervalSince(last) < waistCacheTTL,
           let cached = cachedWaistMeasurements {
            return cached
        }
        
        let fresh = try await fetchWaistMeasurements()
        cachedWaistMeasurements = fresh
        lastWaistFetch = now
        return fresh
    }

    // MARK: - Waist

    func fetchWaistMeasurements() async throws -> [(value: Double, date: Date)] {
        try await store.fetchWaistMeasurements()
    }

    func saveWaistMeasurement(value: Double, date: Date) async throws {
        try await store.saveWaistMeasurement(value: value, date: date)
    }

    func deleteWaistMeasurement(date: Date) async throws {
        try await store.deleteWaistMeasurements(inDay: date)
    }
    
    // MARK: - Import Height to SwiftData
    
    /// Importuje najnowszy wzrost z HealthKit do SwiftData
    func importHeightFromHealthKit(to context: ModelContext) async throws {
        guard let latest = try await fetchLatestHeightInCentimeters() else {
            AppLog.debug("⚠️ No height data in HealthKit")
            return
        }
        
        // Extract date before using in predicate
        let latestDate = latest.date
        
        // Sprawdź czy już nie ma próbki z tą datą
        let descriptor = FetchDescriptor<MetricSample>(
            predicate: #Predicate { sample in
                sample.kindRaw == "height" && sample.date == latestDate
            }
        )
        
        let existing = try? context.fetch(descriptor)
        
        if existing?.isEmpty ?? true {
            // Utwórz nową próbkę
            let sample = MetricSample(
                kind: .height,
                value: latest.value,
                date: latest.date
            )
            context.insert(sample)
            try context.save()
            AppLog.debug("✅ Imported height from HealthKit: \(latest.value) cm")
        } else {
            AppLog.debug("ℹ️ Height sample already exists for this date")
        }
    }
    
    private func importNewQuantities(
        identifier: HKQuantityTypeIdentifier,
        kind: MetricKind,
        unit: HKUnit,
        percent01: Bool
    ) async {
        guard UserDefaults.standard.bool(forKey: "isSyncEnabled") else { return }
        guard UserDefaults.standard.bool(forKey: "healthkit_sync_\(kind.rawValue)") else { return }
        guard let container = modelContainer else { return }

        do {
            let anchorData = storedAnchorData(for: kind)
            let migrationSince = anchorData == nil ? lastProcessedDate(for: kind) : nil
            let anchored = try await store.anchoredQuantitySamples(
                for: identifier,
                unit: unit,
                anchorData: anchorData,
                since: migrationSince
            )
            let samples = anchored.samples
            guard !samples.isEmpty || anchored.newAnchorData != nil else { return }

            let context = ModelContext(container)
            context.autosaveEnabled = false
            let importResult = try importSamples(
                samples,
                for: kind,
                percent01: percent01,
                context: context,
                notifyExternalImports: true
            )

            if importResult.didInsertAny {
                try context.save()
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "healthkit_last_import")
            }

            if let newAnchorData = anchored.newAnchorData {
                setStoredAnchorData(newAnchorData, for: kind)
            }
            if let newestDate = importResult.newestDate {
                setLastProcessedDate(newestDate, for: kind)
            }
        } catch {
            AppLog.debug("⚠️ Failed to import \(kind.rawValue) from HealthKit: \(error)")
        }
    }

    private func storedAnchorData(for kind: MetricKind) -> Data? {
        UserDefaults.standard.data(forKey: anchorDataPrefix + kind.rawValue)
    }

    private func setStoredAnchorData(_ data: Data, for kind: MetricKind) {
        UserDefaults.standard.set(data, forKey: anchorDataPrefix + kind.rawValue)
    }

    private func lastProcessedDate(for kind: MetricKind) -> Date? {
        let value = UserDefaults.standard.double(forKey: processedDatePrefix + kind.rawValue)
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    private func setLastProcessedDate(_ date: Date, for kind: MetricKind) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: processedDatePrefix + kind.rawValue)
    }

    private func importSamples(
        _ rawSamples: [(value: Double, date: Date, sourceBundleID: String?)],
        for kind: MetricKind,
        percent01: Bool,
        context: ModelContext,
        notifyExternalImports: Bool
    ) throws -> (didInsertAny: Bool, newestDate: Date?) {
        guard !rawSamples.isEmpty else { return (didInsertAny: false, newestDate: nil) }

        let normalizedSamples = rawSamples
            .map { item in
                NormalizedImportSample(
                    date: item.date,
                    value: percent01 ? item.value * 100.0 : item.value,
                    sourceBundleID: item.sourceBundleID
                )
            }
            .sorted { $0.date < $1.date }

        guard let firstDate = normalizedSamples.first?.date,
              let lastDate = normalizedSamples.last?.date else {
            return (didInsertAny: false, newestDate: nil)
        }

        let dedupeConfig = dedupeConfig(for: kind)
        let fetchStart = firstDate.addingTimeInterval(-dedupeConfig.dateTolerance)
        let fetchEnd = lastDate.addingTimeInterval(dedupeConfig.dateTolerance)

        let existingSamples = try fetchSamplesForImportDedup(
            kindRaw: kind.rawValue,
            startDate: fetchStart,
            endDate: fetchEnd,
            in: context
        )

        let bucketSize = max(1, dedupeConfig.dateTolerance)
        var indexByTimeBucket: [Int: [ImportComparisonSample]] = [:]
        indexByTimeBucket.reserveCapacity(max(existingSamples.count, normalizedSamples.count))

        for sample in existingSamples {
            let bucket = importBucket(for: sample.date, bucketSize: bucketSize)
            indexByTimeBucket[bucket, default: []].append(
                ImportComparisonSample(date: sample.date, value: sample.value)
            )
        }

        var didInsertAny = false
        var newestDate = Date.distantPast

        for sample in normalizedSamples {
            newestDate = max(newestDate, sample.date)
            let bucket = importBucket(for: sample.date, bucketSize: bucketSize)

            if isDuplicateImportSample(
                date: sample.date,
                value: sample.value,
                bucket: bucket,
                indexByTimeBucket: indexByTimeBucket,
                dateTolerance: dedupeConfig.dateTolerance,
                valueTolerance: dedupeConfig.valueTolerance
            ) {
                continue
            }

            context.insert(MetricSample(kind: kind, value: sample.value, date: sample.date))
            indexByTimeBucket[bucket, default: []].append(
                ImportComparisonSample(date: sample.date, value: sample.value)
            )
            didInsertAny = true

            if notifyExternalImports,
               sample.sourceBundleID == nil || sample.sourceBundleID != appBundleID {
                NotificationManager.shared.sendImportNotification(kind: kind, date: sample.date)
            }
        }

        return (
            didInsertAny: didInsertAny,
            newestDate: newestDate > .distantPast ? newestDate : nil
        )
    }

    private func dedupeConfig(for kind: MetricKind) -> ImportDeduplicationConfig {
        let valueTolerance: Double = kind == .bodyFat ? 0.05 : 0.02
        return ImportDeduplicationConfig(
            dateTolerance: importDateTolerance,
            valueTolerance: valueTolerance
        )
    }

    private func fetchSamplesForImportDedup(
        kindRaw: String,
        startDate: Date,
        endDate: Date,
        in context: ModelContext
    ) throws -> [MetricSample] {
        let descriptor = FetchDescriptor<MetricSample>(
            predicate: #Predicate { sample in
                sample.kindRaw == kindRaw &&
                sample.date >= startDate &&
                sample.date <= endDate
            }
        )
        return try context.fetch(descriptor)
    }

    private func importBucket(for date: Date, bucketSize: TimeInterval) -> Int {
        Int(floor(date.timeIntervalSince1970 / bucketSize))
    }

    private func isDuplicateImportSample(
        date: Date,
        value: Double,
        bucket: Int,
        indexByTimeBucket: [Int: [ImportComparisonSample]],
        dateTolerance: TimeInterval,
        valueTolerance: Double
    ) -> Bool {
        for candidateBucket in (bucket - 1)...(bucket + 1) {
            guard let candidates = indexByTimeBucket[candidateBucket] else { continue }
            for candidate in candidates {
                let isSameDate = abs(candidate.date.timeIntervalSince(date)) <= dateTolerance
                let isSameValue = abs(candidate.value - value) <= valueTolerance
                if isSameDate && isSameValue {
                    return true
                }
            }
        }
        return false
    }
}
