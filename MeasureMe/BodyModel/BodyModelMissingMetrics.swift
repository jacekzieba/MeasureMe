// BodyModelMissingMetrics.swift
//
// **BodyModelMissingMetrics**
// Turns the metrics `BodySnapshotBuilder` reports as missing into something the
// screen can show and something `QuickAddSheetView` can accept.
//
// **Why the two lists differ:**
// The builder reports only the left side of a pair, and only when both sides are
// empty. Naming a side in the list would claim the model cared about one arm; but
// once the user is typing, offering both sides is what the rest of the app does.
// So the list collapses a pair to a neutral body-part name and the sheet expands
// it back to left and right.
//
// Not `nonisolated`: `Row.title` resolves through `AppLocalization` and
// `MetricKind.title`, both of which are MainActor-isolated in this target.
//
import Foundation

enum BodyModelMissingMetrics {

    /// One entry in the list of what the user still has to log.
    struct Row: Identifiable, Equatable {
        /// Stable and unlocalized, so tests and `ForEach` never depend on the display language.
        let id: String
        let title: String
        let systemImage: String
    }

    /// Left side of each pair → the neutral site it collapses to, and the right side it expands back to.
    private static let pairs: [MetricKind: (site: BodyMeasurementSite, right: MetricKind)] = [
        .leftBicep: (.bicep, .rightBicep),
        .leftForearm: (.forearm, .rightForearm),
        .leftThigh: (.thigh, .rightThigh),
        .leftCalf: (.calf, .rightCalf)
    ]

    /// List rows, in the order the builder reported them (already `MetricKind.allCases` order).
    static func rows(for kinds: [MetricKind]) -> [Row] {
        kinds.map { kind in
            guard let pair = pairs[kind] else {
                return Row(id: kind.rawValue, title: kind.title, systemImage: kind.systemImage)
            }
            return Row(
                id: pair.site.localizationKey,
                title: AppLocalization.string(pair.site.localizationKey),
                systemImage: kind.systemImage
            )
        }
    }

    /// Metrics to hand `QuickAddSheetView`, with both sides of every pair.
    static func quickAddKinds(for kinds: [MetricKind]) -> [MetricKind] {
        kinds.flatMap { kind -> [MetricKind] in
            guard let pair = pairs[kind] else { return [kind] }
            return [kind, pair.right]
        }
    }
}
