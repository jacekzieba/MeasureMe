import SwiftUI

struct SettingsCard<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: Content

    init(tint: Color, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            content
        }
        .padding(AppSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppGlassBackground(
                depth: .base,
                cornerRadius: AppRadius.md,
                tint: tint
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }
}

struct SettingsCardHeader: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color(hex: "#FCA311"))
            }
            Text(title)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(.white)
        }
    }
}

struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.24))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

struct SettingsScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
