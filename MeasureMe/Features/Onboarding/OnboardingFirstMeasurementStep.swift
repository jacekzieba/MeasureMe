import SwiftUI

/// Onboarding step 2: lightweight first measurement form.
/// Shows only the recommended metrics for the selected goals (2-4 fields, not 18).
/// Weight is always first and prominent. At least one value required to proceed.
struct OnboardingFirstMeasurementStep: View {
    @FocusState private var focusedKind: MetricKind?

    let recommendedKinds: [MetricKind]
    @Binding var entries: [MetricKind: String]
    let unitsSystem: String
    let isHealthKitSyncEnabled: Bool
    let isRequestingHealthKit: Bool
    let healthKitStatusText: String?
    let onRequestHealthKit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            onboardingSlideHeader(
                title: OnboardingView.Step.firstMeasurement.title,
                subtitle: OnboardingView.Step.firstMeasurement.subtitle
            )

            metricFields
            healthKitPrompt
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissKeyboard()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(AppLocalization.systemString("Done")) {
                    dismissKeyboard()
                }
            }
        }
    }

    // MARK: - Metric fields

    private var metricFields: some View {
        VStack(spacing: 8) {
            ForEach(Array(recommendedKinds.enumerated()), id: \.element) { index, kind in
                let isWeight = kind == .weight
                metricRow(kind: kind, isPrimary: isWeight && index == 0)
            }
        }
    }

    private func metricRow(kind: MetricKind, isPrimary: Bool) -> some View {
        let binding = Binding<String>(
            get: { entries[kind] ?? "" },
            set: { entries[kind] = $0 }
        )

        return HStack(spacing: 12) {
            kind.iconView(size: isPrimary ? 22 : 18, tint: Color.appAccent)
                .frame(width: isPrimary ? 36 : 30, height: isPrimary ? 36 : 30)
                .background(Color.appAccent.opacity(0.16))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(kind.title)
                        .font(isPrimary ? AppTypography.bodyEmphasis : AppTypography.captionEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)

                    if !isPrimary {
                        Text(AppLocalization.systemString("optional"))
                            .font(AppTypography.micro)
                            .foregroundStyle(AppColorRoles.textTertiary)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                TextField(placeholderValue(for: kind), text: binding)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(isPrimary
                          ? .system(size: 24, weight: .bold, design: .rounded).monospacedDigit()
                          : .system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .frame(width: isPrimary ? 90 : 72)
                    .focused($focusedKind, equals: kind)
                    .accessibilityIdentifier("onboarding.measurement.\(kind.rawValue)")

                Text(kind.unitSymbol(unitsSystem: unitsSystem))
                    .font(isPrimary ? AppTypography.bodyEmphasis : AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .frame(width: 26, alignment: .leading)
            }
        }
        .padding(isPrimary ? 14 : 10)
        .background(
            RoundedRectangle(cornerRadius: isPrimary ? 16 : 12, style: .continuous)
                .fill(isPrimary ? Color.appAccent.opacity(0.10) : AppColorRoles.surfaceInteractive)
                .overlay(
                    RoundedRectangle(cornerRadius: isPrimary ? 16 : 12, style: .continuous)
                        .stroke(isPrimary ? Color.appAccent.opacity(0.35) : AppColorRoles.borderSubtle, lineWidth: 1)
                )
        )
    }

    // MARK: - Helpers

    private func placeholderValue(for kind: MetricKind) -> String {
        let isMetric = unitsSystem != "imperial"
        switch kind.unitCategory {
        case .weight:
            return isMetric ? "75.0" : "165.0"
        case .length:
            return isMetric ? "90.0" : "35.0"
        case .percent:
            return "20.0"
        }
    }

    private var healthKitPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLocalization.systemString("Want less manual typing?"))
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(AppColorRoles.textPrimary)

            OnboardingHealthKitStep(
                isSyncEnabled: isHealthKitSyncEnabled,
                isRequesting: isRequestingHealthKit,
                statusText: healthKitStatusText,
                onRequest: onRequestHealthKit
            )
        }
        .padding(.top, 4)
    }

    private func dismissKeyboard() {
        focusedKind = nil
    }
}
