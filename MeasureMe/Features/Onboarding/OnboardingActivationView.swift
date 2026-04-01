import SwiftUI

/// Shown once after onboarding completes, before the user lands on Home.
/// Forks into two paths based on whether HealthKit was accepted.
struct OnboardingActivationView: View {
    enum Path {
        case healthKitAccepted
        case manual
    }

    let path: Path
    let onContinue: () -> Void

    @AppSetting(\.onboarding.activationTriggerQuickAdd) private var activationTriggerQuickAdd: Bool = false
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showSuccessState: Bool = false
    @State private var animateBackdrop: Bool = false

    private var shouldAnimate: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    var body: some View {
        ZStack {
            AppBackground()
            backdrop

            VStack(spacing: 0) {
                Spacer()

                switch path {
                case .healthKitAccepted:
                    healthKitPath
                case .manual:
                    manualPath
                }

                Spacer()
            }
            .padding(.horizontal, AppSpacing.lg)
        }
        .onAppear {
            animateBackdrop = true
            Analytics.shared.track(.activationPrimaryTaskShown)
            if path == .healthKitAccepted {
                scheduleSuccessTransition()
            }
        }
    }

    // MARK: - Path A: HealthKit accepted

    private var healthKitPath: some View {
        VStack(spacing: 28) {
            if showSuccessState {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(AppColorRoles.stateSuccess)
                    .transition(.scale.combined(with: .opacity))

                VStack(spacing: 10) {
                    Text(AppLocalization.systemString("Your baseline is ready"))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.appWhite)
                        .multilineTextAlignment(.center)

                    Text(AppLocalization.systemString("Your history is in. Charts will show your progress over time."))
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))

                Button {
                    Analytics.shared.track(.activationPrimaryTaskCompleted)
                    Analytics.shared.track(.activationFirstMeasurementSuccessViewed)
                    onContinue()
                } label: {
                    Text(AppLocalization.systemString("See my dashboard"))
                        .foregroundStyle(AppColorRoles.textOnAccent)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                }
                .buttonStyle(AppCTAButtonStyle(size: .large, cornerRadius: AppRadius.md))
                .transition(.opacity)

            } else {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(Color.appAccent)

                VStack(spacing: 10) {
                    Text(AppLocalization.systemString("Your data is coming in"))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.appWhite)
                        .multilineTextAlignment(.center)

                    Text(AppLocalization.systemString("We're pulling in your history. Your trends will be ready soon."))
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .multilineTextAlignment(.center)
                }

                ProgressView()
                    .controlSize(.regular)
                    .tint(Color.appAccent)
            }
        }
        .animation(shouldAnimate ? AppMotion.reveal : .none, value: showSuccessState)
    }

    // MARK: - Path B: Manual

    private var manualPath: some View {
        VStack(spacing: 28) {
            Image(systemName: "ruler.fill")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(Color.appAccent)

            VStack(spacing: 10) {
                Text(AppLocalization.systemString("Let's start with one measurement"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.appWhite)
                    .multilineTextAlignment(.center)

                Text(AppLocalization.systemString("This becomes your baseline. Even one check-in unlocks your progress view."))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    Analytics.shared.track(.activationPrimaryTaskCompleted)
                    Analytics.shared.track(.activationFirstMeasurementStarted)
                    activationTriggerQuickAdd = true
                    onContinue()
                } label: {
                    Text(AppLocalization.systemString("Log now"))
                        .foregroundStyle(AppColorRoles.textOnAccent)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                }
                .buttonStyle(AppCTAButtonStyle(size: .large, cornerRadius: AppRadius.md))

                Button {
                    onContinue()
                } label: {
                    Text(AppLocalization.systemString("Skip for now"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textTertiary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.appAccent.opacity(0.25), .clear],
                        center: .center,
                        startRadius: 30,
                        endRadius: 260
                    )
                )
                .frame(width: 360, height: 360)
                .offset(x: animateBackdrop ? 100 : 60, y: animateBackdrop ? -200 : -150)
                .blur(radius: 14)
                .animation(
                    AppMotion.repeating(.easeInOut(duration: 5).repeatForever(autoreverses: true), enabled: shouldAnimate),
                    value: animateBackdrop
                )
        }
        .allowsHitTesting(false)
    }

    // MARK: - Helpers

    private func scheduleSuccessTransition() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if shouldAnimate {
                withAnimation(AppMotion.reveal) {
                    showSuccessState = true
                }
            } else {
                showSuccessState = true
            }
        }
    }
}
