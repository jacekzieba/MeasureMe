import SwiftData
import SwiftUI
import Combine
import LocalAuthentication

// MARK: - Photo Entry

@Model
final class PhotoEntry {
    @Attribute(.externalStorage)
    var imageData: Data

    var thumbnailData: Data?
    var date: Date
    var tags: [PhotoTag]
    var linkedMetrics: [MetricValueSnapshot]

    var thumbnailOrImageData: Data {
        thumbnailData ?? imageData
    }

    var preferredGridImageData: Data {
        if PhotoUtilities.matchesGridThumbnailSpec(thumbnailData) {
            return thumbnailData ?? imageData
        }
        return imageData
    }

    init(
        imageData: Data,
        thumbnailData: Data? = nil,
        date: Date = .now,
        tags: [PhotoTag],
        linkedMetrics: [MetricValueSnapshot] = []
    ) {
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.date = date
        self.tags = tags
        self.linkedMetrics = linkedMetrics
    }
}

@MainActor
final class PhotoPrivacyGate: ObservableObject {
    static let shared = PhotoPrivacyGate()

    @Published private(set) var isUnlocked = false
    @Published private(set) var lastErrorMessage: String?

    private init() {}

    func canDisplayPhotos(requireBiometric: Bool) -> Bool {
        guard requireBiometric else { return true }
        if UITestArgument.isPresent(.mode) { return true }
        return isUnlocked
    }

    func lock() {
        isUnlocked = false
    }

    func unlock(reason: String? = nil) async {
        guard !UITestArgument.isPresent(.mode) else {
            isUnlocked = true
            return
        }

        let context = LAContext()
        var error: NSError?
        let policy: LAPolicy = .deviceOwnerAuthenticationWithBiometrics
        guard context.canEvaluatePolicy(policy, error: &error) else {
            lastErrorMessage = error?.localizedDescription
            return
        }

        do {
            let localizedReason = reason ?? AppLocalization.string("Unlock photos")
            let success = try await context.evaluatePolicy(policy, localizedReason: localizedReason)
            isUnlocked = success
            lastErrorMessage = success ? nil : AppLocalization.string("Could not unlock photos.")
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
