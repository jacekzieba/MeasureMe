import SwiftUI

struct StartupLoadingView: View {
    let statusKey: String
    let progress: Double

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var progressPercentText: String {
        "\(Int((clampedProgress * 100).rounded()))%"
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 20 : 14) {
                ProgressView(value: clampedProgress)
                    .tint(Color.appAccent)
                    .accessibilityIdentifier("startup.loading.progress")
                    .accessibilityLabel(Text(AppLocalization.string("startup.loading.progress.label")))
                    .accessibilityValue(Text(progressPercentText))

                Text(AppLocalization.string(statusKey))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .accessibilityIdentifier("startup.loading.status")
            }
            .frame(maxWidth: 280)
            .padding(.horizontal, 24)
        }
        .accessibilityIdentifier("startup.loading.root")
    }
}
