import SwiftData
import SwiftUI

/// Serwis odpowiedzialny za usuwanie zdjec z bazy SwiftData i czyszczenie cache.
/// MetricSample NIE sa usuwane — to niezalezna historia pomiarow.
/// linkedMetrics (MetricValueSnapshot) sa embeddowane w PhotoEntry i usuwane automatycznie.
enum PhotoDeletionService {

    /// Znane rozmiary miniatur uzywane w aplikacji.
    /// Sluza do konstrukcji kluczy cache do wyrzucenia.
    private static let knownThumbnailSizes: [CGSize] = [
        CGSize(width: 110, height: 120),  // PhotoGridCell
        CGSize(width: 600, height: 600),  // PhotoDetailView
    ]

    /// Usuwa zdjecia z bazy SwiftData i czyści ich wpisy w cache (pamiec + dysk).
    ///
    /// - Parameters:
    ///   - photos: Zbiór zdjec do usuniecia
    ///   - context: ModelContext do zapisu zmian
    ///   - displayScale: Skala ekranu do obliczenia kluczy cache (domyslnie skala glownego okna)
    /// - Throws: Jesli context.save() nie powiedzie sie
    @MainActor
    static func deletePhotos(
        _ photos: Set<PhotoEntry>,
        context: ModelContext,
        displayScale: CGFloat? = nil
    ) throws {
        let modelIDs = Set(photos.map(\.persistentModelID))
        try deletePhotos(
            withPersistentModelIDs: modelIDs,
            context: context,
            displayScale: displayScale
        )
    }

    /// Usuwa zdjęcia po persistentModelID, rozwiązując obiekty w bieżącym ModelContext.
    /// Dzięki temu działa poprawnie także gdy wejściowe PhotoEntry pochodzą z innego contextu.
    @MainActor
    static func deletePhotos(
        withPersistentModelIDs modelIDs: Set<PersistentIdentifier>,
        context: ModelContext,
        displayScale: CGFloat? = nil
    ) throws {
        let resolvedScale = displayScale
            ?? UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.windows.first?.screen.scale }
                .first
            ?? 3.0
        guard !modelIDs.isEmpty else { return }

        let resolvedPhotos = modelIDs.compactMap { context.model(for: $0) as? PhotoEntry }
        guard !resolvedPhotos.isEmpty else { return }

        // 1. Zbierz identyfikatory cache PRZED usunieciem (po delete staja sie niewazne)
        let cacheIDs = resolvedPhotos.map { String(describing: $0.id) }

        // 2. Usun z bazy SwiftData
        for photo in resolvedPhotos {
            context.delete(photo)
        }
        try context.save()

        // 3. Wyrzuc wpisy z cache pamieci (dopasowanie po prefixie)
        for cacheID in cacheIDs {
            ImageCache.shared.removeImages(withPrefix: cacheID)
        }

        // 4. Wyrzuc wpisy z cache dyskowego (jawna konstrukcja kluczy)
        let scale = resolvedScale
        Task {
            for cacheID in cacheIDs {
                var keys: [String] = []
                for size in knownThumbnailSizes {
                    let w = Int(max(size.width * scale, 1))
                    let h = Int(max(size.height * scale, 1))
                    keys.append("\(cacheID)_downsample_\(w)x\(h)")
                }
                await DiskImageCache.shared.removeImages(forKeys: keys)
            }
        }

        AppLog.debug("🗑️ Batch deleted \(resolvedPhotos.count) photos, evicted cache for \(cacheIDs.count) IDs")
    }
}
