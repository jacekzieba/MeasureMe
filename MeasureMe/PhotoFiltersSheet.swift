import SwiftUI

/// Arkusz z filtrami zdjęć
struct PhotoFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var filters: PhotoFilters
    
    var body: some View {
        NavigationStack {
            Form {
                dateRangeSection
                tagsSection
            }
            .navigationTitle(AppLocalization.string("Filters"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Done")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(AppLocalization.string("Reset")) {
                        filters.reset()
                    }
                    .disabled(!filters.isActive)
                }
            }
        }
    }
    
    // MARK: - Date Range Section
    
    private var dateRangeSection: some View {
        Section(AppLocalization.string("Date Range")) {
            Picker("", selection: $filters.dateRange) {
                ForEach(DateRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel(AppLocalization.string("Date Range"))
            
            if filters.dateRange == .custom {
                DatePicker(AppLocalization.string("From"), selection: $filters.customStartDate, displayedComponents: .date)
                DatePicker(AppLocalization.string("To"), selection: $filters.customEndDate, displayedComponents: .date)
            }
            
            if filters.dateRange == .all {
                Text(AppLocalization.string("Showing all photos"))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Tags Section
    
    private var tagsSection: some View {
        Section(AppLocalization.string("Tags")) {
            if filters.selectedTags.isEmpty {
                Text(AppLocalization.string("All tags"))
                    .foregroundStyle(.secondary)
            }
            
            ForEach(PhotoTag.allCases, id: \.self) { tag in
                Toggle(tag.title, isOn: Binding(
                    get: { filters.selectedTags.contains(tag) },
                    set: { isOn in
                        if isOn {
                            filters.selectedTags.insert(tag)
                        } else {
                            filters.selectedTags.remove(tag)
                        }
                    }
                ))
            }
        }
    }
}

// MARK: - Preview

#Preview("Filters Sheet") {
    @Previewable @State var filters = PhotoFilters()
    
    return PhotoFiltersSheet(filters: filters)
}
