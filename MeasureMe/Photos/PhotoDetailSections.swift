import SwiftUI

/// Sekcja z podglądem zdjęcia i opcją pełnoekranowego wyświetlania
struct PhotoPreviewSection: View {
    let imageData: Data
    var cacheID: String? = nil
    let onTapFullScreen: () -> Void
    
    private var imageAspectRatio: CGFloat {
        let size = UIImage(data: imageData)?.size ?? CGSize(width: 4, height: 3)
        return size.width / max(size.height, 1)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            DownsampledImageView(
                imageData: imageData,
                targetSize: CGSize(width: 600, height: 600),
                contentMode: .fill,
                cornerRadius: 12,
                cacheID: cacheID
            )
            .aspectRatio(imageAspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .shadow(radius: 5)
            .onTapGesture {
                onTapFullScreen()
            }
            
            Button {
                onTapFullScreen()
            } label: {
                Label(AppLocalization.string("View Full Screen"), systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Sekcja z datą zdjęcia
struct PhotoDateSection: View {
    let date: Date
    @Binding var editedDate: Date
    let isEditing: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(AppLocalization.string("Date"), systemImage: "calendar")
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(.primary)
            
            if isEditing {
                DatePicker(
                    "Photo Date",
                    selection: $editedDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
            } else {
                HStack {
                    Text(date.formatted(date: .long, time: .shortened))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

/// Sekcja z tagami zdjęcia
struct PhotoTagsSection: View {
    let tags: [PhotoTag]
    @Binding var editedTags: Set<PhotoTag>
    let isEditing: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(AppLocalization.string("Tags"), systemImage: "tag.fill")
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(.primary)
            
            if isEditing {
                TagSelectionGrid(selectedTags: $editedTags)
            } else {
                if tags.isEmpty {
                    emptyStateView
                } else {
                    tagsFlowLayout
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        Text(AppLocalization.string("No tags"))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var tagsFlowLayout: some View {
        FlowLayout(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                TagChip(tag: tag)
            }
        }
    }
}

/// Sekcja z metrykami zdjęcia
struct PhotoMetricsSection: View {
    let metrics: [MetricValueSnapshot]
    @Binding var editedMetrics: [MetricValueSnapshot]
    let metricsStore: ActiveMetricsStore
    let isEditing: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(AppLocalization.string("Metric Snapshots"), systemImage: "chart.bar.fill")
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(.primary)
            
            if isEditing {
                MetricSnapshotsEditor(
                    snapshots: $editedMetrics,
                    metricsStore: metricsStore
                )
            } else {
                if metrics.isEmpty {
                    emptyStateView
                } else {
                    metricsListView
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        Text(AppLocalization.string("No metrics recorded"))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var metricsListView: some View {
        VStack(spacing: 8) {
            ForEach(metrics) { snapshot in
                MetricSnapshotRow(snapshot: snapshot)
            }
        }
    }
}
