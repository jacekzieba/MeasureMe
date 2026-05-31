import SwiftUI
import SwiftData
import UIKit

/// ViewModel for PhotoView — holds pure UI state that does not need to be
/// a SwiftUI binding on a sheet/alert/navigationDestination modifier.
@Observable @MainActor
final class PhotoViewModel {

    // MARK: - Overlay / chooser flags

    var showUITestSourceChooserOverlay = false
    var showPendingLaunchSourceChooser = false
    var didDismissPendingLaunchSourceChooser = false

    // MARK: - Import pipeline state

    var pendingLibrarySelection: MultiPhotoLibrarySelectionPayload? = nil
    var singlePickerImage: UIImage? = nil
    var singlePickerSource: PhotoLibraryImageSource? = nil
    var multiPhotoImportPayload: MultiPhotoImportPayload? = nil

    // MARK: - Feed refresh / recency

    var refreshToken = UUID()
    var recentlySavedPhoto: PhotoEntry?
    var recentlySavedPhotoEventID = UUID()

    // MARK: - Selection mode

    var isSelecting = false

    // MARK: - Hero compare override

    var heroCompareOverride: TemporaryHeroPairOverride?

    // MARK: - UI test guards

    var didRunUITestAutoOpen = false

    // MARK: - Failure toast

    var failureToastMessage: String?
    var showsFailureToast = false

    // MARK: - Picker timing

    var pickerDismissedAt: ContinuousClock.Instant?

    // MARK: - Batch tracking

    var photoBatchByPersistentID: [String: UUID] = [:]
}
