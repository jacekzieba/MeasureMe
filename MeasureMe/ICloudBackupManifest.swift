import Foundation

struct ICloudBackupManifest: Codable, Sendable {
    let schemaVersion: Int
    let createdAt: Date
    let metricsCount: Int
    let goalsCount: Int
    let photosCount: Int
    let settingsCount: Int
    let isEncrypted: Bool
    let sizeBytes: Int64?

    nonisolated init(
        schemaVersion: Int,
        createdAt: Date,
        metricsCount: Int,
        goalsCount: Int,
        photosCount: Int,
        settingsCount: Int,
        isEncrypted: Bool,
        sizeBytes: Int64? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.metricsCount = metricsCount
        self.goalsCount = goalsCount
        self.photosCount = photosCount
        self.settingsCount = settingsCount
        self.isEncrypted = isEncrypted
        self.sizeBytes = sizeBytes
    }
}
