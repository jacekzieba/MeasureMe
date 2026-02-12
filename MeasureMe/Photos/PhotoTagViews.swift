import SwiftUI

/// Chip z tagiem do wyświetlania
struct TagChip: View {
    let tag: PhotoTag
    
    var body: some View {
        Text(tag.title)
            .font(AppTypography.captionEmphasis)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.appAccent)
            .clipShape(Capsule())
    }
}

/// Tag selection grid dla trybu edycji
struct TagSelectionGrid: View {
    @Binding var selectedTags: Set<PhotoTag>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(tagGroups, id: \.title) { group in
                TagGroupView(
                    group: group,
                    selectedTags: $selectedTags
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var tagGroups: [(title: String, tags: [PhotoTag])] {
        [
            ("Special", [.wholeBody]),
            ("Body Size", [.height, .waist]),
            ("Upper Body", [.neck, .shoulders, .bust, .chest]),
            ("Arms", [.leftBicep, .rightBicep, .leftForearm, .rightForearm]),
            ("Lower Body", [.hips, .leftThigh, .rightThigh, .leftCalf, .rightCalf])
        ]
    }
}

/// Pojedyncza grupa tagów
private struct TagGroupView: View {
    let group: (title: String, tags: [PhotoTag])
    @Binding var selectedTags: Set<PhotoTag>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.title)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(.secondary)
            
            FlowLayout(spacing: 8) {
                ForEach(group.tags, id: \.self) { tag in
                    SelectableTagChip(
                        tag: tag,
                        isSelected: selectedTags.contains(tag)
                    ) {
                        toggleTag(tag)
                    }
                }
            }
        }
    }
    
    private func toggleTag(_ tag: PhotoTag) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
}

/// Wybieralny chip z tagiem
struct SelectableTagChip: View {
    let tag: PhotoTag
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AppTypography.micro)
                }
                Text(tag.title)
            }
            .font(AppTypography.captionEmphasis)
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.appAccent : Color(.systemGray5))
            .clipShape(Capsule())
        }
    }
}

#Preview("Tag Chip") {
    TagChip(tag: .wholeBody)
}

#Preview("Tag Selection Grid") {
    @Previewable @State var selectedTags: Set<PhotoTag> = [.wholeBody, .waist]
    
    return TagSelectionGrid(selectedTags: $selectedTags)
        .padding()
}
