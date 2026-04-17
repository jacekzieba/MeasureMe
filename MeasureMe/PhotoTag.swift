import SwiftUI
import UIKit
import Vision
import ImageIO

enum PhotoTag: String, Codable, CaseIterable, Identifiable, Sendable {

    // MARK: - Primary Pose
    case front
    case side
    case back
    case detail

    // MARK: - Legacy / Advanced
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

// MARK: - pomocniki UI
extension PhotoTag {

    static let primaryPoseTags: [PhotoTag] = [.front, .side, .back, .detail]

    static let legacyAreaTags: [PhotoTag] = [
        .wholeBody,
        .height,
        .waist,
        .neck,
        .shoulders,
        .bust,
        .chest,
        .leftBicep,
        .rightBicep,
        .leftForearm,
        .rightForearm,
        .hips,
        .leftThigh,
        .rightThigh,
        .leftCalf,
        .rightCalf
    ]

    var isPrimaryPose: Bool {
        Self.primaryPoseTags.contains(self)
    }

    var isLegacyAreaTag: Bool {
        !isPrimaryPose
    }

    static func primaryPose(in tags: [PhotoTag]) -> PhotoTag? {
        tags.first(where: \.isPrimaryPose)
    }

    var shortLabel: String {
        switch self {
        case .front: return "F"
        case .side: return "S"
        case .back: return "B"
        case .detail: return AppLocalization.string("Detail")
        case .wholeBody: return AppLocalization.string("Body")
        default:
            return String(title.prefix(1)).uppercased()
        }
    }

    var title: String {
        switch self {
        case .front: return AppLocalization.string("Front")
        case .side: return AppLocalization.string("Side")
        case .back: return AppLocalization.string("Back")
        case .detail: return AppLocalization.string("Detail")
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
    
    // Alias dla spojnosci miedzy widokami
    var displayName: String { title }
    
    // Ikona systemowa dla tagu
    var systemImage: String {
        switch self {
        case .front: return "figure.stand"
        case .side: return "figure.stand.line.dotted.figure.stand"
        case .back: return "figure.stand"
        case .detail: return "scope"
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

enum PhotoPoseClassifier {
    static func suggestedPose(for image: UIImage) async -> PhotoTag? {
        guard let cgImage = image.cgImage else { return nil }

        return await Task.detached(priority: .userInitiated) {
            let request = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))

            do {
                try handler.perform([request])
                guard let observation = request.results?.first else { return nil }
                return classify(observation)
            } catch {
                AppLog.debug("⚠️ PhotoPoseClassifier failed: \(error.localizedDescription)")
                return nil
            }
        }.value
    }

    nonisolated private static func classify(_ observation: VNHumanBodyPoseObservation) -> PhotoTag? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }
        let confidentPoints = points.values.filter { $0.confidence >= 0.35 }
        guard confidentPoints.count >= 8 else { return nil }

        let pairedPoints = [
            points[.leftShoulder],
            points[.rightShoulder],
            points[.leftHip],
            points[.rightHip]
        ].compactMap { $0 }
        let visiblePairs = pairedPoints.filter { $0.confidence >= 0.35 }.count

        if visiblePairs <= 2 {
            return .side
        }

        return .front
    }
}

private extension CGImagePropertyOrientation {
    nonisolated init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:
            self = .up
        case .upMirrored:
            self = .upMirrored
        case .down:
            self = .down
        case .downMirrored:
            self = .downMirrored
        case .left:
            self = .left
        case .leftMirrored:
            self = .leftMirrored
        case .right:
            self = .right
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
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

    var metricKind: MetricKind? {
        switch self {
        case .front, .side, .back, .detail, .wholeBody:
            return nil
        case .height:
            return .height
        case .waist:
            return .waist
        case .neck:
            return .neck
        case .shoulders:
            return .shoulders
        case .bust:
            return .bust
        case .chest:
            return .chest
        case .leftBicep:
            return .leftBicep
        case .rightBicep:
            return .rightBicep
        case .leftForearm:
            return .leftForearm
        case .rightForearm:
            return .rightForearm
        case .hips:
            return .hips
        case .leftThigh:
            return .leftThigh
        case .rightThigh:
            return .rightThigh
        case .leftCalf:
            return .leftCalf
        case .rightCalf:
            return .rightCalf
        }
    }
}
