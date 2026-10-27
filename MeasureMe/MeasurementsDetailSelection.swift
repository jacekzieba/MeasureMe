import Foundation

/// What the Measurements screen has open. The compact stack pushes `path`; the regular-width split
/// (an open iPhone Duo) shows its last entry in the detail column. Both read the same value, so
/// folding or unfolding the device keeps the open detail.
struct MeasurementsDetailSelection: Equatable {
    enum Route: Hashable {
        case metric(MetricKind)
        case customMetric(String)
    }

    var path: [Route] = []

    mutating func openMetric(_ kind: MetricKind) {
        path = [.metric(kind)]
    }

    mutating func openCustomMetric(_ identifier: String) {
        path = [.customMetric(identifier)]
    }

    /// A custom metric switched off in Settings has no detail to show, so the compact stack must not
    /// keep it (it would push an empty page with only a Back button).
    mutating func dropUntrackedCustomMetrics(activeCustomIdentifiers: [String]) {
        path.removeAll { route in
            if case .customMetric(let identifier) = route {
                return !activeCustomIdentifiers.contains(identifier)
            }
            return false
        }
    }

    /// The split's detail column. Before anything is picked — or when the open custom metric is no
    /// longer tracked — it shows the first active metric, built-in or else custom, rather than an
    /// empty pane. `nil` only when nothing is tracked at all.
    func splitDetail(activeKinds: [MetricKind], activeCustomIdentifiers: [String]) -> Route? {
        switch path.last {
        case .metric(let kind):
            return .metric(kind)
        case .customMetric(let identifier) where activeCustomIdentifiers.contains(identifier):
            return .customMetric(identifier)
        default:
            break
        }
        if let kind = activeKinds.first {
            return .metric(kind)
        }
        return activeCustomIdentifiers.first.map(Route.customMetric)
    }
}
