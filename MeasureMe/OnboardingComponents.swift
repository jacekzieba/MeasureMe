import SwiftUI

struct OnboardingFeatureCard: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(AppTypography.iconMedium)
                .foregroundStyle(Color.appAccent)
                .frame(width: 32, height: 32)
                .background(AppColorRoles.surfaceAccentSoft)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(Color.appWhite)
                Text(detail)
                    .font(AppTypography.caption)
                    .foregroundStyle(Color.appGray)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColorRoles.surfaceInteractive)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
        )
    }
}

struct OnboardingHeroView: View {
    let animate: Bool
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColorRoles.surfacePrimary)
                .frame(height: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppColorRoles.borderStrong, lineWidth: 1)
                )

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppLocalization.systemString("Weekly check-ins"))
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(Color.appGray)
                    Text(AppLocalization.systemString("Waist -1.8 cm"))
                        .font(AppTypography.bodyEmphasis)
                        .monospacedDigit()
                        .foregroundStyle(Color.appWhite)
                    Text(AppLocalization.systemString("Weight -0.9 kg"))
                        .font(AppTypography.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.appGray)
                }

                Spacer()

                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(AppTypography.iconHero)
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 60, height: 60)
                    .background(AppColorRoles.surfaceAccentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 18)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.appAccent.opacity(0.25), lineWidth: 1)
                .opacity(animate ? 1 : 0)
        )
        .scaleEffect(animate ? 1 : 0.96)
        .opacity(animate ? 1 : 0)
        .offset(y: animate ? 0 : 8)
        .animation(AppMotion.animation(.easeOut(duration: 0.6), enabled: shouldAnimate), value: animate)
    }

    private var shouldAnimate: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }
}

struct OnboardingEmptyStateCard: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(AppTypography.iconMedium)
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 30, height: 30)
                    .background(AppColorRoles.surfaceAccentSoft)
                    .clipShape(Circle())

                Text(title)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(Color.appWhite)
            }

            Text(detail)
                .font(AppTypography.caption)
                .foregroundStyle(Color.appGray)
        }
        .padding(14)
        .background(AppColorRoles.surfaceInteractive)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
        )
    }
}
