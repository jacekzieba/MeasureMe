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

/// Pozy oferowane na pasku w aparacie.
enum CameraOverlayPose {

    /// `detail` celowo pominięty — zbliżenie na fragment ciała nie nadaje się na ghost
    /// do dopasowania kadru. Tag nadal istnieje i jest wybieralny w formularzu zdjęcia.
    static let selectable: [PhotoTag] = [.front, .side, .back]

    /// Zamienia zapisaną surową wartość na pozę oferowaną w aparacie.
    /// Zwraca nil dla pustej wartości, nieznanego tagu oraz tagu, którego już nie oferujemy —
    /// dzięki temu `detail` zapisany przez starszą wersję cofa się do „Wył.” zamiast
    /// zostawiać ghost bez zaznaczonej pozycji na pasku.
    static func resolve(storedValue: String) -> PhotoTag? {
        guard let pose = PhotoTag(rawValue: storedValue), selectable.contains(pose) else { return nil }
        return pose
    }
}

/// Krycie ghost-overlaya w aparacie, regulowane suwakiem.
enum CameraOverlayOpacity {

    static let range: ClosedRange<Double> = 0.05...0.50
    static let defaultValue: Double = 0.22

    /// Sprowadza zapisaną wartość do dopuszczalnego zakresu.
    /// Wartości spoza zakresu przycina, a niepoprawne (NaN, nieskończoność) zastępuje domyślną.
    static func clamped(_ raw: Double) -> Double {
        guard raw.isFinite else { return defaultValue }
        return min(max(raw, range.lowerBound), range.upperBound)
    }

    /// Etykieta procentowa pokazywana przy suwaku, np. `22%`.
    static func percentLabel(for value: Double) -> String {
        "\(Int((clamped(value) * 100).rounded()))%"
    }
}
