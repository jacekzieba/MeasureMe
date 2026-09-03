// BodyModelPrewarm.swift
//
// **BodyReconcileCache / BodyModelPrewarm**
// Keeps the body model's expensive work off the screen's critical path.
//
// **Responsibilities:**
// - Memoising volume reconciliation, which is pure and costs 209 ms per snapshot
// - Warming the mesh rig and the newest snapshot after launch and after a save
//
// **Why memoise `reconcile` rather than the screen's whole result:**
// It is a pure function of a `BodySnapshot`, so one cache serves every caller —
// the screen, the prewarm, and a date change that revisits a snapshot already
// seen. Caching the screen's state instead would help only the screen, and
// would need invalidating on inputs the cache cannot see.
//
// **Why the cache is unbounded:**
// A key is one dated snapshot of twelve measurements. Reaching a size worth
// evicting would take more distinct anchor dates than a person accumulates in
// years, and the process does not outlive the app.
//
import Foundation
import SwiftData

@MainActor
enum BodyReconcileCache {
    private static var entries: [BodySnapshot: (parameters: BodyMeshParameters, validation: BodyValidationResult)] = [:]

    static func cached(_ snapshot: BodySnapshot) -> (parameters: BodyMeshParameters, validation: BodyValidationResult)? {
        entries[snapshot]
    }

    static func store(
        _ snapshot: BodySnapshot,
        _ result: (parameters: BodyMeshParameters, validation: BodyValidationResult)
    ) {
        entries[snapshot] = result
    }

    /// Reconciles off the main actor unless the answer is already known.
    static func resolve(_ snapshot: BodySnapshot) async -> (parameters: BodyMeshParameters, validation: BodyValidationResult) {
        if let hit = entries[snapshot] { return hit }
        let computed = await Task.detached(priority: .userInitiated) {
            BodyVolumeValidator.reconcile(snapshot: snapshot)
        }.value
        entries[snapshot] = (computed.parameters, computed.validation)
        return (computed.parameters, computed.validation)
    }

    static func removeAll() { entries.removeAll() }
}

@MainActor
enum BodyModelPrewarm {
    private static var task: Task<Void, Never>?

    /// Builds the rig and pre-solves the newest snapshot in the background.
    ///
    /// Called after launch and after every measurement save, so opening the
    /// body model finds both already done. Cheap to call repeatedly: the rig
    /// build returns immediately once cached, and so does the reconcile.
    /// `settingsStore` defaults to `.shared`, resolved inside the body: a default argument
    /// expression is evaluated in a nonisolated context, which cannot touch the main
    /// actor-isolated singleton.
    static func warm(context: ModelContext, settingsStore: AppSettingsStore? = nil) {
        let settingsStore = settingsStore ?? .shared
        task?.cancel()
        // Inherits the main actor deliberately: ModelContext is not Sendable, so
        // the fetch stays here. Only reconciliation goes detached, and that is
        // the part that costs 209 ms.
        task = Task {
            let profile = settingsStore.snapshot.profile
            guard let gender = BodyGender(Gender(rawValue: profile.userGender) ?? .notSpecified) else { return }

            await BodyBaseMeshProvider.prepare(for: gender)
            guard !Task.isCancelled else { return }

            let samples = (try? context.fetch(
                FetchDescriptor<MetricSample>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            )) ?? []
            guard let newest = samples.map(\.date).max() else { return }

            let built = BodySnapshotBuilder.build(
                samples: samples, anchorDate: newest,
                gender: gender, age: profile.userAge,
                fallbackHeightCm: profile.manualHeight
            )
            guard case let .success(snapshot) = built, !Task.isCancelled else { return }
            _ = await resolve(snapshot)
        }
    }

    private static func resolve(_ snapshot: BodySnapshot) async -> (parameters: BodyMeshParameters, validation: BodyValidationResult) {
        await BodyReconcileCache.resolve(snapshot)
    }
}
