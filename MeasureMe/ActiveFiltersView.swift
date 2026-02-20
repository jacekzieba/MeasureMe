import SwiftUI

/// Kompaktowy widok pokazujący aktywne filtry
struct ActiveFiltersView: View {
    let filters: PhotoFilters
    let onClearAll: () -> Void
    
    var body: some View {
        if filters.isActive {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if filters.dateRange != .all {
                        FilterChip(
                            icon: "calendar",
                            title: filters.dateRange.title
                        )
                    }
                    
                    // Tags chips
                    if !filters.selectedTags.isEmpty {
                        FilterChip(
                            icon: "tag.fill",
                            title: AppLocalization.plural("photos.tags.count", filters.selectedTags.count)
                        )
                    }
                    
                    // Przycisk wyczysc wszystko
                    Button {
                        onClearAll()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                            Text(AppLocalization.string("Clear"))
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .clipShape(Capsule())
                    }
                    .accessibilityLabel(AppLocalization.string("Clear all filters"))
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(.ultraThinMaterial)
        }
    }
}

private struct FilterChip: View {
    let icon: String
    let title: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.appAccent)
        .clipShape(Capsule())
    }
}

#Preview {
    let filters1 = PhotoFilters()
    filters1.dateRange = .last30Days
    filters1.selectedTags = [.wholeBody, .waist]
    
    return VStack {
        ActiveFiltersView(filters: filters1) {
            AppLog.debug("Clear all")
        }
        
        Spacer()
    }
}
