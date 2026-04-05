import SwiftUI

struct HomeActivationSnapshot {
    let stepIndex: Int
    let totalSteps: Int
    let title: String
    let body: String
    let primaryCTA: String
    let skipCTA: String
    let dismissCTA: String
}

struct HomeActivationCard: View {
    let snapshot: HomeActivationSnapshot
    let onPrimary: () -> Void
    let onSkip: () -> Void
    let onDismiss: () -> Void

    private let theme: FeatureTheme = .home

    var body: some View {
        HomeWidgetCard(
            tint: theme.strongTint.opacity(0.26),
            depth: .elevated,
            contentPadding: 18,
            accessibilityIdentifier: "home.module.activationHub"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(OnboardingCopy.activationEyebrow)
                            .font(AppTypography.microEmphasis)
                            .foregroundStyle(Color.appAccent)
                        Text(OnboardingCopy.activationTitle)
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(AppColorRoles.textPrimary)
                        Text(OnboardingCopy.activationSubtitle(step: snapshot.stepIndex, total: snapshot.totalSteps))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColorRoles.textSecondary)
                    }

                    Spacer()

                    Menu {
                        Button(snapshot.dismissCTA, action: onDismiss)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColorRoles.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                ProgressView(value: Double(snapshot.stepIndex), total: Double(snapshot.totalSteps))
                    .tint(Color.appAccent)

                VStack(alignment: .leading, spacing: 10) {
                    Text(snapshot.title)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColorRoles.textPrimary)
                    Text(snapshot.body)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                }
                .accessibilityIdentifier("home.activation.title")

                HStack(spacing: 10) {
                    Button(action: onPrimary) {
                        Text(snapshot.primaryCTA)
                            .foregroundStyle(AppColorRoles.textOnAccent)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                    }
                    .buttonStyle(AppCTAButtonStyle(size: .regular, cornerRadius: AppRadius.md))
                    .accessibilityIdentifier("home.activation.primary")

                    Button(action: onSkip) {
                        Text(snapshot.skipCTA)
                            .frame(minHeight: 48)
                            .padding(.horizontal, 14)
                    }
                    .buttonStyle(AppSecondaryButtonStyle(cornerRadius: AppRadius.md))
                    .accessibilityIdentifier("home.activation.skip")
                }
            }
        }
    }
}

struct ActivationMetricSelectionSheet: View {
    let recommendedKinds: [MetricKind]
    @ObservedObject var metricsStore: ActiveMetricsStore
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(FlowLocalization.app(
                        "Choose the metrics that deserve space on your home and quick-add surfaces.",
                        "Wybierz metryki, które mają trafić na home i do szybkiego dodawania.",
                        "Elige las métricas que merecen espacio en inicio y en el acceso rápido.",
                        "Wähle die Messwerte, die Platz auf Home und im Schnellzugriff bekommen sollen.",
                        "Choisissez les mesures qui méritent une place sur l'accueil et dans l'ajout rapide.",
                        "Escolha as métricas que merecem espaço na home e na adição rápida."
                    ))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                }

                Section {
                    ForEach(metricsStore.allKindsInOrder, id: \.self) { kind in
                        Toggle(isOn: metricsStore.binding(for: kind)) {
                            HStack(spacing: 12) {
                                kind.iconView(font: AppTypography.iconSmall, size: 18, tint: Color.appAccent)
                                    .frame(width: 26, height: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kind.title)
                                    if recommendedKinds.contains(kind) {
                                        Text(FlowLocalization.app("Recommended", "Polecane", "Recomendado", "Empfohlen", "Recommandé", "Recomendado"))
                                            .font(AppTypography.micro)
                                            .foregroundStyle(Color.appAccent)
                                    }
                                }
                            }
                        }
                        .tint(Color.appAccent)
                    }
                }
            }
            .navigationTitle(OnboardingCopy.activationTaskTitle(.chooseMetrics))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Done")) {
                        onDone()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ActivationPremiumExplainerView: View {
    let onContinueFree: () -> Void
    let onSeePremium: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppScreenBackground(topHeight: 360, tint: FeatureTheme.premium.strongTint.opacity(0.32))

            VStack(alignment: .leading, spacing: 18) {
                Spacer(minLength: 0)

                Text(OnboardingCopy.premiumTitle)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.appWhite)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(OnboardingCopy.premiumBullets, id: \.self) { bullet in
                        Label(bullet, systemImage: "sparkles")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColorRoles.textSecondary)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    onSeePremium()
                    dismiss()
                } label: {
                    Text(FlowLocalization.app("See Premium", "Zobacz Premium", "Ver Premium", "Premium ansehen", "Voir Premium", "Ver Premium"))
                        .foregroundStyle(AppColorRoles.textOnAccent)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                }
                .buttonStyle(AppCTAButtonStyle(size: .regular, cornerRadius: AppRadius.md))

                Button {
                    onContinueFree()
                    dismiss()
                } label: {
                    Text(FlowLocalization.app("Continue with free plan", "Kontynuuj w planie darmowym", "Continuar con plan gratis", "Mit Gratisplan fortfahren", "Continuer avec le plan gratuit", "Continuar no plano grátis"))
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
    }
}
