import SwiftUI

struct StartupErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            AppScreenBackground(topHeight: 320, tint: Color.red.opacity(0.18))

            VStack(alignment: .leading, spacing: 16) {
                Label {
                    Text(AppLocalization.string("Startup failed"))
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColorRoles.textPrimary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.red.opacity(0.9))
                }

                Text(message)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Haptics.light()
                    onRetry()
                } label: {
                    Text(AppLocalization.string("Retry"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppAccentButtonStyle(cornerRadius: 12))
            }
            .padding(18)
            .background(
                AppGlassBackground(
                    depth: .elevated,
                    cornerRadius: 20,
                    tint: AppColorRoles.surfaceAccentSoft
                )
            )
            .padding(.horizontal, 20)
        }
    }
}
