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

    /// Biometrics with the device passcode as fallback.
    ///
    /// `.deviceOwnerAuthenticationWithBiometrics` has no second way in: a Face ID lockout after
    /// repeated failures, an unenrolled device, or biometry the user disabled all leave the
    /// photos permanently unreachable.
    static let authenticationPolicy: LAPolicy = .deviceOwnerAuthentication

    /// `false` only when the device has no passcode at all — nothing can satisfy the lock then,
    /// so the setting must not be offered.
    static func isAuthenticationAvailable(context: LAContext = LAContext()) -> Bool {
        var error: NSError?
        return context.canEvaluatePolicy(authenticationPolicy, error: &error)
    }

    private init() {}

    func canDisplayPhotos(requireBiometric: Bool) -> Bool {
        guard requireBiometric else { return true }
        #if DEBUG
        if UITestArgument.isPresent(.mode) { return true }
        #endif
        return isUnlocked
    }

    func lock() {
        isUnlocked = false
    }

    func unlock(reason: String? = nil) async {
        #if DEBUG
        guard !UITestArgument.isPresent(.mode) else {
            isUnlocked = true
            return
        }
        #endif

        let context = LAContext()
        let policy = Self.authenticationPolicy
        var error: NSError?
        guard context.canEvaluatePolicy(policy, error: &error) else {
            // The only realistic failure for this policy is a device with no passcode set,
            // so point at the fix instead of surfacing the LAError text.
            lastErrorMessage = AppLocalization.string("Set a device passcode to unlock photos.")
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
