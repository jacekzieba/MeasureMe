import AppIntents
import Foundation
import SwiftData

enum IntentMetricKind: String, AppEnum, CaseIterable, Sendable {
    case weight
    case bodyFat
    case leanBodyMass
    case waist
    case neck
    case shoulders
    case bust
    case chest
    case leftBicep
    case rightBicep
    case leftForearm
    case rightForearm
    case hips
    case leftThigh
    case rightThigh
    case leftCalf
    case rightCalf

    static var typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("intent.metric.type", table: "AppIntents")
    )

    static var caseDisplayRepresentations: [IntentMetricKind: DisplayRepresentation] = [
        .weight: DisplayRepresentation(title: LocalizedStringResource("intent.metric.weight", table: "AppIntents")),
        .bodyFat: DisplayRepresentation(title: LocalizedStringResource("intent.metric.bodyFat", table: "AppIntents")),
        .leanBodyMass: DisplayRepresentation(title: LocalizedStringResource("intent.metric.leanBodyMass", table: "AppIntents")),
        .waist: DisplayRepresentation(title: LocalizedStringResource("intent.metric.waist", table: "AppIntents")),
        .neck: DisplayRepresentation(title: LocalizedStringResource("intent.metric.neck", table: "AppIntents")),
        .shoulders: DisplayRepresentation(title: LocalizedStringResource("intent.metric.shoulders", table: "AppIntents")),
        .bust: DisplayRepresentation(title: LocalizedStringResource("intent.metric.bust", table: "AppIntents")),
        .chest: DisplayRepresentation(title: LocalizedStringResource("intent.metric.chest", table: "AppIntents")),
        .leftBicep: DisplayRepresentation(title: LocalizedStringResource("intent.metric.leftBicep", table: "AppIntents")),
        .rightBicep: DisplayRepresentation(title: LocalizedStringResource("intent.metric.rightBicep", table: "AppIntents")),
        .leftForearm: DisplayRepresentation(title: LocalizedStringResource("intent.metric.leftForearm", table: "AppIntents")),
        .rightForearm: DisplayRepresentation(title: LocalizedStringResource("intent.metric.rightForearm", table: "AppIntents")),
        .hips: DisplayRepresentation(title: LocalizedStringResource("intent.metric.hips", table: "AppIntents")),
        .leftThigh: DisplayRepresentation(title: LocalizedStringResource("intent.metric.leftThigh", table: "AppIntents")),
        .rightThigh: DisplayRepresentation(title: LocalizedStringResource("intent.metric.rightThigh", table: "AppIntents")),
        .leftCalf: DisplayRepresentation(title: LocalizedStringResource("intent.metric.leftCalf", table: "AppIntents")),
        .rightCalf: DisplayRepresentation(title: LocalizedStringResource("intent.metric.rightCalf", table: "AppIntents"))
    ]

    var metricKind: MetricKind {
        switch self {
        case .weight: return .weight
        case .bodyFat: return .bodyFat
        case .leanBodyMass: return .leanBodyMass
        case .waist: return .waist
        case .neck: return .neck
        case .shoulders: return .shoulders
        case .bust: return .bust
        case .chest: return .chest
        case .leftBicep: return .leftBicep
        case .rightBicep: return .rightBicep
        case .leftForearm: return .leftForearm
        case .rightForearm: return .rightForearm
        case .hips: return .hips
        case .leftThigh: return .leftThigh
        case .rightThigh: return .rightThigh
        case .leftCalf: return .leftCalf
        case .rightCalf: return .rightCalf
        }
    }

    init?(metricKind: MetricKind) {
        self.init(rawValue: metricKind.rawValue)
    }
}

enum AppIntentMetricResolver {
    nonisolated private static let orderedMetricFlags: [(MetricKind, String)] = [
        (.weight, "metric_weight_enabled"),
        (.bodyFat, "metric_bodyFat_enabled"),
        (.leanBodyMass, "metric_nonFatMass_enabled"),
        (.waist, "metric_waist_enabled"),
        (.neck, "metric_neck_enabled"),
        (.shoulders, "metric_shoulders_enabled"),
        (.bust, "metric_bust_enabled"),
        (.chest, "metric_chest_enabled"),
        (.leftBicep, "metric_leftBicep_enabled"),
        (.rightBicep, "metric_rightBicep_enabled"),
        (.leftForearm, "metric_leftForearm_enabled"),
        (.rightForearm, "metric_rightForearm_enabled"),
        (.hips, "metric_hips_enabled"),
        (.leftThigh, "metric_leftThigh_enabled"),
        (.rightThigh, "metric_rightThigh_enabled"),
        (.leftCalf, "metric_leftCalf_enabled"),
        (.rightCalf, "metric_rightCalf_enabled")
    ]

    nonisolated static func activeMetrics(defaults: UserDefaults = .standard) -> [MetricKind] {
        orderedMetricFlags.compactMap { kind, key in
            defaults.bool(forKey: key) ? kind : nil
        }
    }

    nonisolated static func activeIntentMetrics(defaults: UserDefaults = .standard) -> [IntentMetricKind] {
        activeMetrics(defaults: defaults).compactMap(IntentMetricKind.init(metricKind:))
    }
}

enum AddMeasurementIntentError: LocalizedError, Equatable {
    case noActiveMetrics
    case metricNotActive
    case invalidValue(message: String)
    case storageFailure

    var errorDescription: String? {
        switch self {
        case .noActiveMetrics:
            return String(localized: "intent.addMeasurement.error.noActiveMetrics", table: "AppIntents")
        case .metricNotActive:
            return String(localized: "intent.addMeasurement.error.metricNotActive", table: "AppIntents")
        case .invalidValue(let message):
            return message
        case .storageFailure:
            return String(localized: "intent.addMeasurement.error.storage", table: "AppIntents")
        }
    }
}

enum AddMeasurementIntentValidator {
    static func validateAndConvert(
        metric: IntentMetricKind,
        inputValue: Double,
        unitsSystem: String,
        activeMetrics: Set<MetricKind>
    ) throws -> (kind: MetricKind, metricValue: Double) {
        let metricKind = metric.metricKind
        guard !activeMetrics.isEmpty else { throw AddMeasurementIntentError.noActiveMetrics }
        guard activeMetrics.contains(metricKind) else { throw AddMeasurementIntentError.metricNotActive }

        let validation = MetricInputValidator.validateMetricDisplayValue(
            inputValue,
            kind: metricKind,
            unitsSystem: unitsSystem
        )

        guard validation.isValid else {
            throw AddMeasurementIntentError.invalidValue(message: validation.message ?? "")
        }

        return (metricKind, metricKind.valueToMetric(fromDisplay: inputValue, unitsSystem: unitsSystem))
    }
}

struct ActiveMetricIntentOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [IntentMetricKind] {
        AppIntentMetricResolver.activeIntentMetrics()
    }
}

enum AppIntentModelContainerProvider {
    static func makePersistentContainer() throws -> ModelContainer {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AddMeasurementIntentError.storageFailure
        }
        try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

        let schema = Schema([
            MetricSample.self,
            MetricGoal.self,
            PhotoEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

struct OpenQuickAddIntent: AppIntent {
    static let title = LocalizedStringResource("intent.openQuickAdd.title", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.openQuickAdd.description", table: "AppIntents"))
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            AppEntryActionDispatcher.enqueue(.openQuickAdd, source: .appIntent)
        }
        return .result(dialog: IntentDialog(LocalizedStringResource("intent.openQuickAdd.success", table: "AppIntents")))
    }
}

struct OpenQuickAddMetricIntent: AppIntent {
    static let title = LocalizedStringResource("intent.openQuickAddMetric.title", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.openQuickAddMetric.description", table: "AppIntents"))
    static let openAppWhenRun = true

    @Parameter(
        title: LocalizedStringResource("intent.openQuickAddMetric.metric", table: "AppIntents"),
        optionsProvider: ActiveMetricIntentOptionsProvider()
    )
    var metric: IntentMetricKind

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            AppNavigationRouteDispatcher.enqueue(.quickAdd(kindRaw: metric.metricKind.rawValue))
        }
        return .result(dialog: IntentDialog(LocalizedStringResource("intent.openQuickAdd.success", table: "AppIntents")))
    }
}

struct OpenAddPhotoIntent: AppIntent {
    static let title = LocalizedStringResource("intent.openAddPhoto.title", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.openAddPhoto.description", table: "AppIntents"))
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            AppEntryActionDispatcher.enqueue(.openAddPhoto, source: .appIntent)
        }
        return .result(dialog: IntentDialog(LocalizedStringResource("intent.openAddPhoto.success", table: "AppIntents")))
    }
}

struct AddMeasurementIntent: AppIntent {
    static let title = LocalizedStringResource("intent.addMeasurement.title", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.addMeasurement.description", table: "AppIntents"))
    static let openAppWhenRun = false

    @Parameter(
        title: LocalizedStringResource("intent.addMeasurement.metric", table: "AppIntents"),
        optionsProvider: ActiveMetricIntentOptionsProvider()
    )
    var metric: IntentMetricKind

    @Parameter(title: LocalizedStringResource("intent.addMeasurement.value", table: "AppIntents"))
    var value: Double

    @Parameter(title: LocalizedStringResource("intent.addMeasurement.date", table: "AppIntents"))
    var date: Date?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let defaults = UserDefaults(suiteName: "group.com.jacek.measureme") ?? .standard
        let unitsSystem = defaults.string(forKey: "unitsSystem") ?? "metric"
        let activeMetrics = Set(AppIntentMetricResolver.activeMetrics(defaults: defaults))
        let validated = try await MainActor.run {
            try AddMeasurementIntentValidator.validateAndConvert(
                metric: metric,
                inputValue: value,
                unitsSystem: unitsSystem,
                activeMetrics: activeMetrics
            )
        }
        let timestamp = date ?? AppClock.now

        try await MainActor.run {
            let container = try AppIntentModelContainerProvider.makePersistentContainer()
            let context = ModelContext(container)
            let saveService = QuickAddSaveService(context: context)
            try saveService.save(
                entries: [.init(kind: validated.kind, metricValue: validated.metricValue)],
                date: timestamp,
                unitsSystem: unitsSystem
            )

            if validated.kind.isHealthSynced {
                IntentDeferredHealthSyncStore.enqueue(
                    kind: validated.kind,
                    metricValue: validated.metricValue,
                    date: timestamp
                )
            }
        }

        await MainActor.run {
            Analytics.shared.track(
                signalName: "com.jacekzieba.measureme.app_intent_measurement_saved",
                parameters: ["kind": validated.kind.rawValue]
            )
        }

        return .result(dialog: IntentDialog(LocalizedStringResource("intent.addMeasurement.success", table: "AppIntents")))
    }
}

struct MeasureMeAppShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenQuickAddIntent(),
            phrases: [
                "Open Quick Add in \(.applicationName)",
                "Quick Add in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("intent.shortcut.quickAdd.shortTitle", table: "AppIntents"),
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: OpenAddPhotoIntent(),
            phrases: [
                "Open Add Photo in \(.applicationName)",
                "Add Photo in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("intent.shortcut.addPhoto.shortTitle", table: "AppIntents"),
            systemImageName: "camera.fill"
        )
        AppShortcut(
            intent: AddMeasurementIntent(),
            phrases: [
                "Add measurement in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("intent.shortcut.addMeasurement.shortTitle", table: "AppIntents"),
            systemImageName: "ruler"
        )
    }

    static var shortcutTileColor: ShortcutTileColor = .orange
}
