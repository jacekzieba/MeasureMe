import Foundation

/// Wybiera zdjęcie-overlay dla każdej z głównych póz.
enum PhotoOverlayCandidates {

    /// Najnowsze dane obrazu dla każdej z póz `PhotoTag.primaryPoseTags`.
    /// - Parameter photos: lista posortowana malejąco po dacie.
    static func mostRecentByPose(in photos: [PhotoEntry]) -> [PhotoTag: Data] {
        var result: [PhotoTag: Data] = [:]

        for photo in photos {
            for tag in photo.tags where tag.isPrimaryPose && result[tag] == nil {
                result[tag] = photo.thumbnailOrImageData
            }
            if result.count == PhotoTag.primaryPoseTags.count { break }
        }

        return result
    }
}

/// Trzy poziomy krycia ghost-overlaya w aparacie.
enum CameraOverlayOpacity: Int, CaseIterable {
    case light = 0
    case medium = 1
    case strong = 2

    init(storedValue: Int) {
        self = CameraOverlayOpacity(rawValue: storedValue) ?? .medium
    }

    var value: Double {
        switch self {
        case .light: return 0.12
        case .medium: return 0.22
        case .strong: return 0.35
        }
    }

    var next: CameraOverlayOpacity {
        CameraOverlayOpacity(rawValue: (rawValue + 1) % CameraOverlayOpacity.allCases.count) ?? .light
    }
}
