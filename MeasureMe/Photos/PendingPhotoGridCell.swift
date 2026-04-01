import SwiftUI

struct PendingPhotoGridCell: View {
    @Environment(\.colorScheme) private var colorScheme
    let thumbnailData: Data
    let progress: Double
    let status: PendingPhotoSaveStatus
    let targetSize: CGSize
    let cornerRadius: CGFloat
    let cacheID: String
    var showsStatusLabel: Bool = true
    var accessibilityIdentifier: String? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            DownsampledImageView(
                imageData: thumbnailData,
                targetSize: targetSize,
                contentMode: .fill,
                cornerRadius: cornerRadius,
                showsProgress: false,
                cacheID: "pending_\(cacheID)"
            )

            Rectangle()
                .fill(colorScheme == .dark ? Color.black.opacity(0.62) : Color.black.opacity(0.44))

            VStack(alignment: .leading, spacing: 4) {
                if showsStatusLabel {
                    Text(status.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                ProgressView(value: min(max(progress, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(Color.appAccent)
                    .scaleEffect(x: 1, y: 0.9, anchor: .center)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.14) : AppColorRoles.borderSubtle, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppLocalization.string("Photo"))
        .accessibilityValue("\(status.title), \(Int(progress * 100))%")
        .pendingAccessibilityIdentifier(accessibilityIdentifier)
    }
}

private extension View {
    @ViewBuilder
    func pendingAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            self.accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}
