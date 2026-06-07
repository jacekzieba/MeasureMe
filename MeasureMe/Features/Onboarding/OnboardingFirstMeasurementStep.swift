import SwiftUI

/// Onboarding step 2: lightweight first measurement form.
/// Shows only the recommended metrics for the selected goal. At least one value is required to proceed.
struct OnboardingFirstMeasurementStep: View {
    @FocusState private var focusedKind: MetricKind?

    let recommendedKinds: [MetricKind]
    @Binding var entries: [MetricKind: String]
    let unitsSystem: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                onboardingSlideHeader(
                    title: OnboardingView.Step.firstMeasurement.title,
                    subtitle: OnboardingView.Step.firstMeasurement.subtitle
                )
                Spacer(minLength: 0)
                MeasureBuddyView(pose: .goals, size: 72)
                    .padding(.top, -2)
            }

            Text(
                FlowLocalization.app(
                    "Enter whatever you have now. You can add more later.",
                    "Wpisz tyle, ile masz teraz. Resztę dodasz później.",
                    "Escribe lo que tengas ahora. Podrás añadir más después.",
                    "Trage ein, was du jetzt hast. Den Rest kannst du später ergänzen.",
                    "Saisissez ce que vous avez maintenant. Vous pourrez ajouter le reste plus tard.",
                    "Digite o que você tiver agora. Você pode adicionar mais depois."
                )
            )
            .font(AppTypography.caption)
            .foregroundStyle(AppColorRoles.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            metricFields
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
                metricRow(kind: kind, isPrimary: index == 0)
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
                    .accessibilityLabel("\(kind.title) \(AppLocalization.systemString("value"))")
                    .accessibilityValue(entries[kind] ?? "")

                Text(kind.unitSymbol(unitsSystem: unitsSystem))
                    .font(isPrimary ? AppTypography.bodyEmphasis : AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .frame(width: 26, alignment: .leading)
            }
        }
        .padding(isPrimary ? AppSpacing.smmd : 10)
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

    private func dismissKeyboard() {
        focusedKind = nil
    }
}
