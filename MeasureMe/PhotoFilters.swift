import Foundation
import SwiftData
import Combine

// MARK: - Photo Filters Model

final class PhotoFilters: ObservableObject {
    
    // MARK: - Date Range
    @Published var dateRange: DateRange = .all
    @Published var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
    @Published var customEndDate: Date = .now
    
    // MARK: - Tags
    @Published var selectedTags: Set<PhotoTag> = []
    
    // MARK: - Computed
    var isActive: Bool {
        dateRange != .all || !selectedTags.isEmpty
    }
    
    var activeFiltersCount: Int {
        var count = 0
        if dateRange != .all { count += 1 }
        if !selectedTags.isEmpty { count += 1 }
        return count
    }
    
    // MARK: - Actions
    func reset() {
        dateRange = .all
        customStartDate = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        customEndDate = .now
        selectedTags.removeAll()
    }
    
    // MARK: - Predicate Generation
    func buildPredicate() -> Predicate<PhotoEntry>? {
        let hasDateFilter = dateRange != .all
        let hasTagsFilter = !selectedTags.isEmpty
        
        // Jeśli mamy tylko domyślny filtr daty (all) i brak filtra tagów
        if !hasDateFilter && !hasTagsFilter {
            return nil
        }
        
        // Get values for closures
        let startDate = dateRange.startDate(customStart: customStartDate)
        let endDate = dateRange.endDate(customEnd: customEndDate)
        let tagsArray = Array(selectedTags)
        
        // Build combined predicate
        if hasTagsFilter {
            // Z tagami
            guard let start = startDate, let end = endDate else {
                return tagsOnlyPredicate(tags: tagsArray)
            }
            
            return #Predicate<PhotoEntry> { photo in
                photo.date >= start && 
                photo.date <= end &&
                tagsArray.contains(where: { tag in photo.tags.contains(tag) })
            }
        } else {
            // Date filter only (jeśli nie jest domyślny)
            guard let start = startDate, let end = endDate else { return nil }
            
            return #Predicate<PhotoEntry> { photo in
                photo.date >= start && photo.date <= end
            }
        }
    }
    
    private func tagsOnlyPredicate(tags: [PhotoTag]) -> Predicate<PhotoEntry> {
        #Predicate<PhotoEntry> { photo in
            tags.contains(where: { tag in photo.tags.contains(tag) })
        }
    }

    // MARK: - In-memory filtering
    func matches(_ photo: PhotoEntry) -> Bool {
        let matchesDate: Bool
        if let start = dateRange.startDate(customStart: customStartDate),
           let end = dateRange.endDate(customEnd: customEndDate) {
            matchesDate = photo.date >= start && photo.date <= end
        } else {
            matchesDate = true
        }

        let matchesTags: Bool
        if selectedTags.isEmpty {
            matchesTags = true
        } else {
            matchesTags = !selectedTags.isDisjoint(with: Set(photo.tags))
        }

        return matchesDate && matchesTags
    }
}

// MARK: - Date Range Enum

enum DateRange: String, CaseIterable, Identifiable {
        case all
        case last7Days
        case last30Days
        case last90Days
        case custom
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .all:
            return AppLocalization.string("photos.dateRange.all")
        case .last7Days:
            return AppLocalization.string("photos.dateRange.last7Days")
        case .last30Days:
            return AppLocalization.string("photos.dateRange.last30Days")
        case .last90Days:
            return AppLocalization.string("photos.dateRange.last90Days")
        case .custom:
            return AppLocalization.string("photos.dateRange.custom")
        }
    }
    
    func startDate(customStart: Date) -> Date? {
        let calendar = Calendar.current
        let now = Date.now
        
        switch self {
        case .all:
            return nil
        case .last7Days:
            return calendar.date(byAdding: .day, value: -7, to: now)
        case .last30Days:
            return calendar.date(byAdding: .day, value: -30, to: now)
        case .last90Days:
            return calendar.date(byAdding: .day, value: -90, to: now)
        case .custom:
            return calendar.startOfDay(for: customStart)
        }
    }
    
    func endDate(customEnd: Date) -> Date? {
        let calendar = Calendar.current

        switch self {
        case .all:
            return nil
        case .custom:
            let start = calendar.startOfDay(for: customEnd)
            return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start)
        default:
            return Date.now
        }
    }
}
