import SwiftUI
import SwiftData

// MARK: - Home Compare Pair

struct HomeComparePair: Identifiable {
    let olderPhoto: PhotoEntry
    let newerPhoto: PhotoEntry

    var id: String {
        "\(olderPhoto.persistentModelID)-\(newerPhoto.persistentModelID)"
    }
}

// MARK: - Home Health Stat Item

struct HomeHealthStatItem: Identifiable {
    var id: String { label }
    let label: String
    let value: String
    let badge: String?

    init(label: String, value: String, badge: String? = nil) {
        self.label = label
        self.value = value
        self.badge = badge
    }
}

// MARK: - Home Next Focus Insight

struct HomeNextFocusInsight {
    enum Action {
        case metric(MetricKind)
        case measurements
    }

    let headline: String?
    let primaryValue: String?
    let supportingLabel: String?
    let contextLabel: String
    let summary: String
    let cta: String
    let action: Action
    let accessibilityValue: String
}

// MARK: - Home Next Focus Candidate

struct HomeNextFocusCandidate {
    let insight: HomeNextFocusInsight
    let score: Double
}

// MARK: - Photo Sync Snapshot Payload

struct PhotoSyncSnapshotPayload: Sendable {
    let kindRaw: String
    let value: Double
    let date: Date
}

// MARK: - Photo Sync Candidate Payload

struct PhotoSyncCandidatePayload: Sendable {
    let date: Date
    let linkedMetrics: [PhotoSyncSnapshotPayload]
}

// MARK: - Photo Sync Mode

enum PhotoSyncMode {
    case full
    case incremental
}

// MARK: - Day Part

enum DayPart {
    case morning
    case afternoon
    case evening
}

// MARK: - Module Header Action

struct ModuleHeaderAction: Identifiable {
    let id = UUID()
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void
}

// MARK: - Home Photo Tile

enum HomePhotoTile: Identifiable {
    case persisted(PhotoEntry)
    case pending(PendingPhotoSaveItem)

    var id: String {
        switch self {
        case .persisted(let photo):
            return "persisted_\(String(describing: photo.persistentModelID))"
        case .pending(let item):
            return "pending_\(item.id.uuidString)"
        }
    }

    var date: Date {
        switch self {
        case .persisted(let photo):
            return photo.date
        case .pending(let item):
            return item.date
        }
    }
}
