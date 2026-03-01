import SwiftUI

/// Krok 2 onboardingu — HealthKit sync i przypomnienia.
struct OnboardingBoostersStep: View {
    let isSyncEnabled: Bool
    let isReminderScheduled: Bool
    let isRequestingHealthKit: Bool
    let isRequestingNotifications: Bool

    let onRequestHealthKit: () -> Void
    let onSetupReminder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            onboardingSlideHeader(title: OnboardingView.Step.boosters.title, subtitle: OnboardingView.Step.boosters.subtitle)

            boosterCard(
                icon: "heart.text.square",
                title: AppLocalization.systemString("Sync with Apple Health"),
                detail: AppLocalization.systemString("Import history and keep measurements updated automatically."),
                why: AppLocalization.systemString("Why: your charts start with more context."),
                buttonTitle: isSyncEnabled ? AppLocalization.systemString("Connected") : AppLocalization.systemString("Next"),
                isLoading: isRequestingHealthKit,
                isComplete: isSyncEnabled,
                buttonIdentifier: "onboarding.booster.healthkit",
                action: onRequestHealthKit
            )

            boosterCard(
                icon: "bell.badge",
                title: AppLocalization.systemString("Measurement reminders"),
                detail: AppLocalization.systemString("Choose one-time, daily or weekly schedule."),
                why: AppLocalization.systemString("Why: gentle nudges keep you consistent."),
                buttonTitle: isReminderScheduled ? AppLocalization.systemString("Scheduled") : AppLocalization.systemString("Set schedule"),
                isLoading: isRequestingNotifications,
                isComplete: isReminderScheduled,
                buttonIdentifier: "onboarding.booster.reminders",
                action: onSetupReminder
            )
        }
    }

    // MARK: - Booster card

    private func boosterCard(
        icon: String,
        title: String,
        detail: String,
        why: String,
        buttonTitle: String,
        isLoading: Bool,
        isComplete: Bool,
        buttonIdentifier: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            OnboardingFeatureCard(icon: icon, title: title, detail: detail)

            Text(why)
                .font(AppTypography.caption)
                .foregroundStyle(Color.appGray)

            Button {
                action()
            } label: {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.appAccent)
                    }
                    Text(buttonTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .tint(Color.appAccent)
            .disabled(isLoading || isComplete)
            .accessibilityIdentifier(buttonIdentifier ?? "")
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
