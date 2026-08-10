import Foundation
import SwiftData

struct PhotoComparePair: Identifiable {
    let presentationID = UUID()
    let olderPhoto: PhotoEntry
    let newerPhoto: PhotoEntry

    var id: String {
        "\(olderPhoto.persistentModelID)_\(newerPhoto.persistentModelID)_\(presentationID.uuidString)"
    }
}

/// Decyduje, kiedy ekran porównania ma się pokazać: od razu, czy dopiero po zamknięciu
/// sheeta, z którego przyszło żądanie.
struct ComparePresentationState {
    private(set) var active: PhotoComparePair?
    private(set) var pending: PhotoComparePair?

    mutating func request(_ pair: PhotoComparePair, presentedFromSheet: Bool) {
        if presentedFromSheet {
            pending = pair
        } else {
            active = pair
        }
    }

    mutating func sheetDismissed() {
        guard let pair = pending else { return }
        pending = nil
        active = pair
    }

    mutating func activeDismissed() {
        active = nil
    }
}
