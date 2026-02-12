import SwiftUI
import SwiftData

/// Utility do migracji i optymalizacji istniejących zdjęć w bazie danych
/// Używane do jednorazowej konwersji starych, nieskompresowanych zdjęć
enum PhotoMigrationUtility {
    
    // MARK: - Migration Status
    
    /// Sprawdza czy migracja jest potrzebna
    @MainActor
    static func needsMigration(context: ModelContext) async -> Bool {
        do {
            let descriptor = FetchDescriptor<PhotoEntry>()
            let photos = try context.fetch(descriptor)
            
            // Sprawdź czy któreś zdjęcie jest większe niż 3MB (oznacza brak kompresji)
            let largePhotos = photos.filter { $0.imageData.count > 3_000_000 }
            
            AppLog.debug("📊 Migration check: \(largePhotos.count) photos need optimization (out of \(photos.count) total)")
            
            return !largePhotos.isEmpty
        } catch {
            AppLog.debug("❌ Migration check failed: \(error)")
            return false
        }
    }
    
    // MARK: - Migration Execution
    
    /// Migruje wszystkie zdjęcia do nowego formatu (resize + compression)
    /// - Parameters:
    ///   - context: ModelContext do operacji na danych
    ///   - progressHandler: Callback z postępem (0.0 - 1.0)
    @MainActor
    static func migrateAllPhotos(
        context: ModelContext,
        progressHandler: ((Double, String) -> Void)? = nil
    ) async throws {
        let descriptor = FetchDescriptor<PhotoEntry>()
        let photos = try context.fetch(descriptor)
        
        AppLog.debug("🔄 Starting photo migration for \(photos.count) photos...")
        
        var migratedCount = 0
        var skippedCount = 0
        var failedCount = 0
        var totalSavedBytes: Int64 = 0
        
        for (index, photo) in photos.enumerated() {
            let progress = Double(index) / Double(photos.count)
            let message = "Processing photo \(index + 1) of \(photos.count)..."
            progressHandler?(progress, message)
            
            // Skip jeśli już skompresowane (< 2.5MB)
            if photo.imageData.count <= 2_500_000 {
                skippedCount += 1
                continue
            }
            
            guard let originalImage = UIImage(data: photo.imageData) else {
                AppLog.debug("❌ Failed to decode photo \(photo.id)")
                failedCount += 1
                continue
            }
            
            let originalSize = photo.imageData.count
            
            // Optymalizuj: resize + compress
            let optimized = originalImage
                .resized(maxDimension: 1920)
                .fixedOrientation()
            
            guard let compressedData = optimized.compressed(toMaxSize: 2_000_000) else {
                AppLog.debug("❌ Failed to compress photo \(photo.id)")
                failedCount += 1
                continue
            }
            
            // Zapisz nowe dane
            photo.imageData = compressedData
            
            let savedBytes = originalSize - compressedData.count
            totalSavedBytes += Int64(savedBytes)
            
            AppLog.debug("✅ Migrated photo \(photo.id): \(PhotoUtilities.formatFileSize(originalSize)) → \(PhotoUtilities.formatFileSize(compressedData.count))")
            
            migratedCount += 1
            
            // Zapisz co 10 zdjęć aby zmniejszyć memory footprint
            if migratedCount.isMultiple(of: 10) {
                try context.save()
                AppLog.debug("💾 Saved batch of 10 photos")
            }
        }
        
        // Finalne zapisanie
        try context.save()
        
        progressHandler?(1.0, "Migration complete!")
        
        AppLog.debug("""
        ✅ Photo migration complete!
        - Migrated: \(migratedCount) photos
        - Skipped: \(skippedCount) photos (already optimized)
        - Failed: \(failedCount) photos
        - Total space saved: \(PhotoUtilities.formatFileSize(Int(totalSavedBytes)))
        """)
    }
    
    // MARK: - Single Photo Migration
    
    /// Migruje pojedyncze zdjęcie (przydatne do on-demand optimization)
    @MainActor
    static func migratePhoto(_ photo: PhotoEntry, context: ModelContext) throws {
        guard let originalImage = UIImage(data: photo.imageData) else {
            throw MigrationError.invalidImageData
        }
        
        let originalSize = photo.imageData.count
        
        // Skip jeśli już skompresowane
        if originalSize <= 2_500_000 {
            AppLog.debug("⏭️ Photo already optimized, skipping")
            return
        }
        
        let optimized = originalImage
            .resized(maxDimension: 1920)
            .fixedOrientation()
        
        guard let compressedData = optimized.compressed(toMaxSize: 2_000_000) else {
            throw MigrationError.compressionFailed
        }
        
        photo.imageData = compressedData
        try context.save()
        
        let savedBytes = originalSize - compressedData.count
        AppLog.debug("✅ Migrated photo: saved \(PhotoUtilities.formatFileSize(savedBytes))")
    }
    
    // MARK: - Statistics
    
    /// Zwraca statystyki dotyczące zdjęć w bazie
    @MainActor
    static func getPhotoStatistics(context: ModelContext) async -> PhotoStatistics {
        do {
            let descriptor = FetchDescriptor<PhotoEntry>()
            let photos = try context.fetch(descriptor)
            
            var totalSize: Int64 = 0
            var largestPhoto: Int = 0
            var smallestPhoto: Int = Int.max
            var needsOptimization = 0
            
            for photo in photos {
                let size = photo.imageData.count
                totalSize += Int64(size)
                largestPhoto = max(largestPhoto, size)
                smallestPhoto = min(smallestPhoto, size)
                
                if size > 2_500_000 {
                    needsOptimization += 1
                }
            }
            
            let averageSize = photos.isEmpty ? 0 : totalSize / Int64(photos.count)
            
            return PhotoStatistics(
                totalPhotos: photos.count,
                totalSize: totalSize,
                averageSize: averageSize,
                largestPhoto: largestPhoto,
                smallestPhoto: photos.isEmpty ? 0 : smallestPhoto,
                needsOptimization: needsOptimization
            )
        } catch {
            AppLog.debug("❌ Failed to get statistics: \(error)")
            return PhotoStatistics()
        }
    }
}

// MARK: - Supporting Types

struct PhotoStatistics {
    var totalPhotos: Int = 0
    var totalSize: Int64 = 0
    var averageSize: Int64 = 0
    var largestPhoto: Int = 0
    var smallestPhoto: Int = 0
    var needsOptimization: Int = 0
    
    var totalSizeFormatted: String {
        PhotoUtilities.formatFileSize(Int(totalSize))
    }
    
    var averageSizeFormatted: String {
        PhotoUtilities.formatFileSize(Int(averageSize))
    }
    
    var largestPhotoFormatted: String {
        PhotoUtilities.formatFileSize(largestPhoto)
    }
    
    var smallestPhotoFormatted: String {
        PhotoUtilities.formatFileSize(smallestPhoto)
    }
}

enum MigrationError: LocalizedError {
    case invalidImageData
    case compressionFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "Invalid image data - cannot decode photo"
        case .compressionFailed:
            return "Failed to compress photo"
        }
    }
}

// MARK: - SwiftUI View for Migration

/// Widok do przeprowadzenia migracji zdjęć
struct PhotoMigrationView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @State private var needsMigration = false
    @State private var isChecking = true
    @State private var isMigrating = false
    @State private var progress: Double = 0.0
    @State private var statusMessage = ""
    @State private var statistics: PhotoStatistics?
    @State private var migrationComplete = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if isChecking {
                    checkingView
                } else if migrationComplete {
                    completionView
                } else if needsMigration {
                    migrationNeededView
                } else {
                    noMigrationNeededView
                }
            }
            .padding()
            .navigationTitle(AppLocalization.string("Photo Optimization"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Close")) {
                        dismiss()
                    }
                    .disabled(isMigrating)
                }
            }
            .task {
                await checkMigrationStatus()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var checkingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(AppLocalization.string("Checking photos..."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private var migrationNeededView: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.badge.arrow.down")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
            
            VStack(spacing: 8) {
                Text(AppLocalization.string("Optimization Available"))
                    .font(.title2)
                    .fontWeight(.bold)
                
                if let stats = statistics {
                    Text(AppLocalization.plural("photos.optimization.count", stats.needsOptimization))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        StatRow(label: "Total photos:", value: "\(stats.totalPhotos)")
                        StatRow(label: "Total size:", value: stats.totalSizeFormatted)
                        StatRow(label: "Average size:", value: stats.averageSizeFormatted)
                        StatRow(label: "Largest photo:", value: stats.largestPhotoFormatted)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            
            if isMigrating {
                VStack(spacing: 12) {
                    ProgressView(value: progress)
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task {
                        await performMigration()
                    }
                } label: {
                    Label(AppLocalization.string("Optimize Photos"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            
            Text(AppLocalization.string("This will reduce photo file sizes while maintaining quality. Photos will be resized to max 1920px and compressed to ~2MB."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var noMigrationNeededView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            
            Text(AppLocalization.string("All photos are optimized!"))
                .font(.title2)
                .fontWeight(.bold)
            
            if let stats = statistics {
                VStack(alignment: .leading, spacing: 8) {
                    StatRow(label: "Total photos:", value: "\(stats.totalPhotos)")
                    StatRow(label: "Total size:", value: stats.totalSizeFormatted)
                    StatRow(label: "Average size:", value: stats.averageSizeFormatted)
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private var completionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            
            Text(AppLocalization.string("Migration Complete!"))
                .font(.title2)
                .fontWeight(.bold)
            
            Text(AppLocalization.string("All photos have been optimized."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button(AppLocalization.string("Done")) {
                dismiss()
            }
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Actions
    
    private func checkMigrationStatus() async {
        statistics = await PhotoMigrationUtility.getPhotoStatistics(context: context)
        needsMigration = await PhotoMigrationUtility.needsMigration(context: context)
        isChecking = false
    }
    
    private func performMigration() async {
        isMigrating = true
        
        do {
            try await PhotoMigrationUtility.migrateAllPhotos(context: context) { prog, message in
                Task { @MainActor in
                    progress = prog
                    statusMessage = message
                }
            }
            
            // Odśwież statystyki
            statistics = await PhotoMigrationUtility.getPhotoStatistics(context: context)
            migrationComplete = true
        } catch {
            AppLog.debug("❌ Migration failed: \(error)")
            statusMessage = "Migration failed: \(error.localizedDescription)"
        }
        
        isMigrating = false
    }
}

// MARK: - Supporting Views

private struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: PhotoEntry.self, configurations: config)
    
    return PhotoMigrationView()
        .modelContainer(container)
}
