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
                            title: filters.dateRange.title,
                            onRemove: {
                                filters.dateRange = .all
                            }
                        )
                    }
                    
                    // Tags chips
                    ForEach(Array(filters.selectedTags).sorted { $0.title < $1.title }, id: \.self) { tag in
                        FilterChip(
                            icon: "tag.fill",
                            title: tag.title,
                            onRemove: {
                                filters.selectedTags.remove(tag)
                            }
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
                    }
                    .buttonStyle(AppDestructiveButtonStyle(size: .compact, cornerRadius: 999))
                    .accessibilityLabel(AppLocalization.string("Clear all filters"))
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
    }
}

private struct FilterChip: View {
    let icon: String
    let title: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(title)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.string("Remove filter"))
        }
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(AppColorRoles.textOnAccent)
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
