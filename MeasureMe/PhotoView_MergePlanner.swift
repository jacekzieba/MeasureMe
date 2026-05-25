import SwiftUI
import SwiftData
import UIKit

// MARK: - Single-photo save merge support types

struct SinglePhotoSaveMergeResult {
    let photos: [PhotoEntry]
    let fetchOffset: Int
    let didUpdateList: Bool
}

struct SinglePhotoSaveMergeItem {
    let id: String
    let date: Date
}

struct SinglePhotoSaveMergePlan {
    let orderedIDs: [String]
    let fetchOffset: Int
    let didUpdateList: Bool
}

struct PhotoFeedMergeItem {
    let id: String
    let date: Date
}

enum PhotoFeedMergePlanner {
    static func orderedIDs(
        persisted: [PhotoFeedMergeItem],
        pending: [PhotoFeedMergeItem],
        limit: Int? = nil
    ) -> [String] {
        var combined = pending + persisted
        combined.sort { lhs, rhs in
            if lhs.date == rhs.date { return lhs.id < rhs.id }
            return lhs.date > rhs.date
        }

        var seen: Set<String> = []
        var ordered: [String] = []
        for item in combined where seen.insert(item.id).inserted {
            ordered.append(item.id)
        }

        if let limit {
            return Array(ordered.prefix(limit))
        }
        return ordered
    }
}

enum SinglePhotoSaveMergePlanner {

    static func apply(
        recentlySavedItem: SinglePhotoSaveMergeItem?,
        matchesFilter: Bool,
        items: [SinglePhotoSaveMergeItem],
        hasMore: Bool,
        pageSize: Int,
        fetchOffset: Int
    ) -> SinglePhotoSaveMergePlan {
        guard let recentlySavedItem, matchesFilter else {
            return SinglePhotoSaveMergePlan(
                orderedIDs: items.map(\.id),
                fetchOffset: fetchOffset,
                didUpdateList: false
            )
        }

        let originalItems = items
        var updatedItems = items
        let removedExisting = updatedItems.removeAllAndReturnCount { $0.id == recentlySavedItem.id } > 0
        let insertIndex = updatedItems.firstIndex(where: { $0.date < recentlySavedItem.date }) ?? updatedItems.count

        if !removedExisting,
           hasMore,
           originalItems.count >= pageSize,
           insertIndex >= pageSize {
            return SinglePhotoSaveMergePlan(
                orderedIDs: originalItems.map(\.id),
                fetchOffset: fetchOffset,
                didUpdateList: false
            )
        }

        updatedItems.insert(recentlySavedItem, at: insertIndex)

        if !removedExisting, hasMore, updatedItems.count > pageSize {
            updatedItems.removeLast()
        }

        var updatedOffset = fetchOffset
        if !removedExisting, hasMore {
            updatedOffset += 1
        }

        return SinglePhotoSaveMergePlan(
            orderedIDs: updatedItems.map(\.id),
            fetchOffset: updatedOffset,
            didUpdateList: true
        )
    }
}

enum SinglePhotoSaveMergeEngine {

    static func apply(
        recentlySavedPhoto: PhotoEntry?,
        filters: PhotoFilters,
        photos: [PhotoEntry],
        hasMore: Bool,
        pageSize: Int,
        fetchOffset: Int
    ) -> SinglePhotoSaveMergeResult {
        guard let recentlySavedPhoto else {
            return SinglePhotoSaveMergeResult(
                photos: photos,
                fetchOffset: fetchOffset,
                didUpdateList: false
            )
        }

        let recentlySavedID = singlePhotoSaveID(for: recentlySavedPhoto)
        let items = photos.map { photo in
            SinglePhotoSaveMergeItem(id: singlePhotoSaveID(for: photo), date: photo.date)
        }
        let plan = SinglePhotoSaveMergePlanner.apply(
            recentlySavedItem: SinglePhotoSaveMergeItem(id: recentlySavedID, date: recentlySavedPhoto.date),
            matchesFilter: filters.matches(recentlySavedPhoto),
            items: items,
            hasMore: hasMore,
            pageSize: pageSize,
            fetchOffset: fetchOffset
        )

        guard plan.didUpdateList else {
            return SinglePhotoSaveMergeResult(
                photos: photos,
                fetchOffset: plan.fetchOffset,
                didUpdateList: false
            )
        }

        var photosByID: [String: PhotoEntry] = [:]
        for photo in photos {
            let id = singlePhotoSaveID(for: photo)
            if photosByID[id] == nil {
                photosByID[id] = photo
            }
        }
        photosByID[recentlySavedID] = recentlySavedPhoto
        let rebuiltPhotos = plan.orderedIDs.compactMap { photosByID[$0] }

        return SinglePhotoSaveMergeResult(photos: rebuiltPhotos, fetchOffset: plan.fetchOffset, didUpdateList: true)
    }
}

extension Array {
    mutating func removeAllAndReturnCount(where shouldBeRemoved: (Element) throws -> Bool) rethrows -> Int {
        let before = count
        try removeAll(where: shouldBeRemoved)
        return before - count
    }
}

func singlePhotoSaveID(for photo: PhotoEntry) -> String {
    String(describing: photo.persistentModelID)
}
