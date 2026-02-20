import SwiftUI
import SwiftData

struct PhotoFilterView: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var filters: PhotoFilters
    
    @Query private var allPhotos: [PhotoEntry]
    
    // Oblicz dostępne tagi z istniejących zdjęć
    private var availableTags: [PhotoTag] {
        var tags = Set<PhotoTag>()
        for photo in allPhotos {
            tags.formUnion(photo.tags)
        }
        
        return tags.sorted { $0.title < $1.title }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground(topHeight: 220, tint: Color.cyan.opacity(0.16))
                Form {
                    dateRangeSection
                    if !availableTags.isEmpty {
                        tagsSection
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(AppLocalization.string("Filter Photos"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Apply")) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                
                ToolbarItem(placement: .bottomBar) {
                    if filters.isActive {
                        Button(AppLocalization.string("Reset Filters"), role: .destructive) {
                            filters.reset()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Sekcja zakresu dat
private extension PhotoFilterView {
    
    var dateRangeSection: some View {
        Section {
            Picker("", selection: $filters.dateRange) {
                ForEach(DateRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .accessibilityLabel(AppLocalization.string("Date Range"))

            if filters.dateRange == .custom {
                DatePicker(
                    AppLocalization.string("From"),
                    selection: $filters.customStartDate,
                    displayedComponents: [.date]
                )

                DatePicker(
                    AppLocalization.string("To"),
                    selection: $filters.customEndDate,
                    displayedComponents: [.date]
                )
            }
        } header: {
            Text(AppLocalization.string("Date Range"))
        } footer: {
            if let start = filters.dateRange.startDate(customStart: filters.customStartDate),
               let end = filters.dateRange.endDate(customEnd: filters.customEndDate) {
                let startText = start.formatted(date: .abbreviated, time: .omitted)
                let endText = end.formatted(date: .abbreviated, time: .omitted)
                Text(AppLocalization.string("photos.showing.range", startText, endText))
            } else if filters.dateRange == .all {
                Text(AppLocalization.string("Showing all photos"))
            }
        }
    }
}

// MARK: - Sekcja tagow
private extension PhotoFilterView {
    
    var tagsSection: some View {
        Section {
            if filters.selectedTags.isEmpty {
                Text(AppLocalization.string("No tags selected"))
                    .foregroundStyle(.secondary)
            }
            
            ForEach(availableTags) { tag in
                tagRow(for: tag)
            }
        } header: {
            HStack {
                Text(AppLocalization.string("Tags"))
                Spacer()
                if !filters.selectedTags.isEmpty {
                    Button(AppLocalization.string("Clear All")) {
                        filters.selectedTags.removeAll()
                    }
                    .font(.caption)
                    .textCase(.none)
                }
            }
        } footer: {
            if !filters.selectedTags.isEmpty {
                Text(AppLocalization.string("photos.showing.tags.selected", filters.selectedTags.count))
            } else {
                Text(AppLocalization.string("Select tags to filter photos. Photos matching any selected tag will be shown."))
            }
        }
    }
    
    func tagRow(for tag: PhotoTag) -> some View {
        Button {
            toggleTag(tag)
        } label: {
            HStack {
                Text(tag.title)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if filters.selectedTags.contains(tag) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.appAccent)
                        .fontWeight(.semibold)
                }
            }
        }
    }
    
    func toggleTag(_ tag: PhotoTag) {
        if filters.selectedTags.contains(tag) {
            filters.selectedTags.remove(tag)
        } else {
            filters.selectedTags.insert(tag)
        }
    }
}

// MARK: - Preview
#Preview {
    PhotoFilterView(filters: PhotoFilters())
}
