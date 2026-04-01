import SwiftUI

struct WhyItMattersItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
}

struct WhyItMattersCard: View {
    let items: [WhyItMattersItem]

    var body: some View {
        HealthInsightCard(tint: AppColorRoles.accentPrimary.opacity(0.08)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppLocalization.string("Why It Matters"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(AppColorRoles.surfaceAccentSoft)
                                    .frame(width: 28, height: 28)

                                Image(systemName: item.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AppColorRoles.accentPrimary)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(AppTypography.bodyEmphasis)
                                    .foregroundStyle(AppColorRoles.textPrimary)
                                Text(item.description)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColorRoles.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct HealthInsightHeroCard<Content: View>: View {
    var accent: Color = FeatureTheme.health.accent
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(
        accent: Color = FeatureTheme.health.accent,
        @ViewBuilder content: () -> Content
    ) {
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                shape
                    .fill(AppColorRoles.surfaceElevated)
                    .overlay(
                        shape.fill(
                            ClaudeLightStyle.directionalGradient(
                                colors: [
                                    accent.opacity(0.20),
                                    Color.appAmber.opacity(0.10),
                                    .clear
                                ],
                                colorScheme: colorScheme,
                                lightColor: accent.opacity(0.10),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    )
                    .overlay(
                        shape.stroke(AppColorRoles.borderStrong, lineWidth: 1)
                    )
            )
            .shadow(color: AppColorRoles.shadowSoft, radius: 16, x: 0, y: 10)
    }
}

struct HealthInsightCard<Content: View>: View {
    var tint: Color = FeatureTheme.health.softTint
    var cornerRadius: CGFloat = 16
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(
        tint: Color = FeatureTheme.health.softTint,
        cornerRadius: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                shape
                    .fill(AppColorRoles.surfacePrimary)
                    .overlay(
                        shape.fill(
                            ClaudeLightStyle.directionalGradient(
                                colors: [
                                    tint.opacity(0.24),
                                    .clear
                                ],
                                colorScheme: colorScheme,
                                lightColor: tint.opacity(0.10),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    )
                    .overlay(
                        shape.stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                    )
            )
            .shadow(color: AppColorRoles.shadowSoft.opacity(colorScheme == .dark ? 0.9 : 0.7), radius: 10, x: 0, y: 5)
    }
}

struct HealthInsightNoteCard<Content: View>: View {
    var accent: Color = FeatureTheme.health.accent
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(
        accent: Color = FeatureTheme.health.accent,
        @ViewBuilder content: () -> Content
    ) {
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                shape
                    .fill(AppColorRoles.surfaceInteractive)
                    .overlay(
                        shape.fill(
                            ClaudeLightStyle.directionalGradient(
                                colors: [
                                    accent.opacity(0.20),
                                    Color.appAmber.opacity(0.10),
                                    .clear
                                ],
                                colorScheme: colorScheme,
                                lightColor: accent.opacity(0.10),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    )
                    .overlay(
                        shape.stroke(accent.opacity(colorScheme == .dark ? 0.32 : 0.22), lineWidth: 1)
                    )
            )
    }
}
