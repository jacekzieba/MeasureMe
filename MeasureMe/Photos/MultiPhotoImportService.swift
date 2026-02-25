import SwiftData
import SwiftUI

/// Serwis odpowiedzialny za batch import wielu zdjęć do SwiftData.
/// Przetwarza każdy obraz (kompresja) i wstawia go jako osobny PhotoEntry.
/// Jeden context.save() dla wszystkich zdjęć — spójny z wzorcem PhotoDeletionService.
enum MultiPhotoImportService {

    struct ImportResult {
        let savedCount: Int
        let failedCount: Int
    }

    /// Importuje tablicę obrazów jako nowe PhotoEntry z wspólnymi metadanymi.
    ///
    /// Kodowanie (JPEG) jest wykonywane w tle (Task.detached), żeby nie blokować
    /// głównego wątku. Tylko `context.insert` i `context.save` działają na MainActor.
    /// Progress callback jest wołany po zakodowaniu każdego zdjęcia — SwiftUI może
    /// odświeżyć pasek postępu przed przystąpieniem do kolejnego.
    ///
    /// - Parameters:
    ///   - images: Obrazy do zaimportowania (już przetworzone przez prepareImportedImage)
    ///   - date: Wspólna data dla wszystkich wpisów
    ///   - tags: Wspólne tagi dla wszystkich wpisów
    ///   - context: ModelContext do zapisu (musi być izolowany do MainActor po stronie wywołującego)
    ///   - progress: Opcjonalny callback z postępem (currentIndex, total) – wołany na MainActor
    /// - Returns: Wynik importu z liczbą zapisanych i nieudanych
    /// - Throws: Jeśli context.save() nie powiedzie się
    @MainActor
    static func importPhotos(
        _ images: [UIImage],
        date: Date,
        tags: [PhotoTag],
        context: ModelContext,
        useBackgroundEncoding: Bool = true,
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> ImportResult {
        guard !images.isEmpty else { return ImportResult(savedCount: 0, failedCount: 0) }

        var savedCount = 0
        var failedCount = 0
        let total = images.count
        var prewarmQueue: [(cacheID: String, imageData: Data)] = []

        for (index, image) in images.enumerated() {
            // Kodowanie w tle — nie blokuje głównego wątku między iteracjami.
            // useBackgroundEncoding=false pozwala na synchroniczne kodowanie w testach
            // (Task.detached + @MainActor deadlockuje w XCTest).
            let encoded: PhotoUtilities.EncodedPhoto?
            if useBackgroundEncoding {
                encoded = await Task.detached(priority: .userInitiated) {
                    PhotoUtilities.encodeForStorage(
                        image,
                        maxSize: 2_000_000,
                        alreadyPrepared: true
                    )
                }.value
            } else {
                encoded = PhotoUtilities.encodeForStorage(
                    image,
                    maxSize: 2_000_000,
                    alreadyPrepared: true
                )
            }

            guard let encoded else {
                AppLog.debug("⚠️ MultiPhotoImportService: Failed to encode image \(index + 1)/\(total)")
                failedCount += 1
                // Aktualizuj postęp mimo błędu
                progress?(index + 1, total)
                continue
            }

            AppLog.debug(
                "📸 MultiPhotoImportService: Encoded \(index + 1)/\(total) format=\(encoded.format) size=\(PhotoUtilities.formatFileSize(encoded.data.count))"
            )

            // Wstaw do kontekstu na MainActor (jesteśmy już na MainActor)
            let entry = PhotoEntry(
                imageData: encoded.data,
                date: date,
                tags: tags,
                linkedMetrics: []
            )
            context.insert(entry)
            savedCount += 1
            prewarmQueue.append((cacheID: String(describing: entry.id), imageData: encoded.data))

            // Zaktualizuj postęp — SwiftUI może teraz odświeżyć UI przed następną iteracją
            progress?(index + 1, total)
        }

        // Jeden save dla wszystkich — spójny z PhotoDeletionService
        try context.save()
        context.processPendingChanges()

        let prewarmItems = Array(prewarmQueue.prefix(24))
        Task.detached(priority: .utility) {
            for item in prewarmItems {
                await ImagePipeline.prewarmRecentPhotoVariants(
                    imageData: item.imageData,
                    cacheID: item.cacheID
                )
            }
        }

        AppLog.debug("✅ MultiPhotoImportService: Saved \(savedCount)/\(total) photos (\(failedCount) failed)")
        return ImportResult(savedCount: savedCount, failedCount: failedCount)
    }
}
