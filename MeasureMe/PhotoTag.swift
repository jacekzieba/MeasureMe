import SwiftUI

enum PhotoTag: String, Codable, CaseIterable, Identifiable {

    // MARK: - Special
    case wholeBody

    // MARK: - Body Size
    case height
    case waist

    // MARK: - Upper Body
    case neck
    case shoulders
    case bust
    case chest

    // MARK: - Arms
    case leftBicep
    case rightBicep
    case leftForearm
    case rightForearm

    // MARK: - Lower Body
    case hips
    case leftThigh
    case rightThigh
    case leftCalf
    case rightCalf

    var id: String { rawValue }
}

// MARK: - UI helpers
extension PhotoTag {

    var title: String {
        switch self {
        case .wholeBody: return AppLocalization.string("photo.tag.wholebody")

        case .height: return MetricKind.height.title
        case .waist: return MetricKind.waist.title

        case .neck: return MetricKind.neck.title
        case .shoulders: return MetricKind.shoulders.title
        case .bust: return MetricKind.bust.title
        case .chest: return MetricKind.chest.title

        case .leftBicep: return MetricKind.leftBicep.title
        case .rightBicep: return MetricKind.rightBicep.title
        case .leftForearm: return MetricKind.leftForearm.title
        case .rightForearm: return MetricKind.rightForearm.title

        case .hips: return MetricKind.hips.title
        case .leftThigh: return MetricKind.leftThigh.title
        case .rightThigh: return MetricKind.rightThigh.title
        case .leftCalf: return MetricKind.leftCalf.title
        case .rightCalf: return MetricKind.rightCalf.title
        }
    }
    
    // Alias for consistency across views
    var displayName: String { title }
    
    // System image for the tag
    var systemImage: String {
        switch self {
        case .wholeBody: return "figure.stand"
        case .height: return "ruler"
        case .waist: return "figure.torso"
        case .neck: return "person.bust"
        case .shoulders: return "figure.arms.open"
        case .bust, .chest: return "figure.torso"
        case .leftBicep, .rightBicep: return "figure.arms.open"
        case .leftForearm, .rightForearm: return "figure.arms.open"
        case .hips: return "figure.torso"
        case .leftThigh, .rightThigh: return "figure.walk"
        case .leftCalf, .rightCalf: return "figure.walk"
        }
    }
}

// MARK: - MetricKind mapping
extension PhotoTag {

    init?(metricKind: MetricKind) {
        switch metricKind {
        // Weight, bodyFat, leanBodyMass nie są już wspierane jako tagi
        case .weight, .bodyFat, .leanBodyMass:
            return nil

        case .height: self = .height
        case .waist: self = .waist

        case .neck: self = .neck
        case .shoulders: self = .shoulders
        case .bust: self = .bust
        case .chest: self = .chest

        case .leftBicep: self = .leftBicep
        case .rightBicep: self = .rightBicep
        case .leftForearm: self = .leftForearm
        case .rightForearm: self = .rightForearm

        case .hips: self = .hips
        case .leftThigh: self = .leftThigh
        case .rightThigh: self = .rightThigh
        case .leftCalf: self = .leftCalf
        case .rightCalf: self = .rightCalf
        }
    }
}
