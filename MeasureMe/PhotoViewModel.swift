import SwiftUI
import SwiftData
import UIKit

/// ViewModel for PhotoView — holds pure UI state that does not need to be
/// a SwiftUI binding on a sheet/alert/navigationDestination modifier.
@MainActor
final class PhotoViewModel: ObservableObject {

    // MARK: - Overlay / chooser flags

    @Published var showUITestSourceChooserOverlay = false
    @Published var showPendingLaunchSourceChooser = false
    @Published var didDismissPendingLaunchSourceChooser = false

    // MARK: - Import pipeline state

    @Published var pendingLibrarySelection: MultiPhotoLibrarySelectionPayload? = nil
    @Published var singlePickerImage: UIImage? = nil
    @Published var singlePickerSource: PhotoLibraryImageSource? = nil
    @Published var multiPhotoImportPayload: MultiPhotoImportPayload? = nil

    // MARK: - Feed refresh / recency

    @Published var refreshToken = UUID()
    @Published var recentlySavedPhoto: PhotoEntry?
    @Published var recentlySavedPhotoEventID = UUID()

    // MARK: - Selection mode

    @Published var isSelecting = false

    // MARK: - Hero compare override

    @Published var heroCompareOverride: TemporaryHeroPairOverride?

    // MARK: - UI test guards

    @Published var didRunUITestAutoOpen = false

    // MARK: - Failure toast

    @Published var failureToastMessage: String?
    @Published var showsFailureToast = false

    // MARK: - Picker timing

    @Published var pickerDismissedAt: ContinuousClock.Instant?

    // MARK: - Batch tracking

    @Published var photoBatchByPersistentID: [String: UUID] = [:]
}
