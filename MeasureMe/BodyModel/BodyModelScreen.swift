// BodyModelScreen.swift
//
// **BodyModelScreen**
// The 3D body model screen, presented from the Photos tab.
//
// **Responsibilities:**
// - Presenting the mannequin and the morph slider between two dates
// - Gating on premium and on data completeness
// - Exposing the change list as the accessible equivalent of the 3D view
//
// The rendered geometry is invisible to VoiceOver, so the MetricChangeRow list
// below it is not decoration — it is how the screen's information reaches
// someone who cannot see the mannequin.
//
import SwiftUI
import SwiftData

struct BodyModelScreen: View {
    @EnvironmentObject private var premiumStore: PremiumStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @AppSetting(\.profile.userGender) private var userGender: String = "notSpecified"
    @AppSetting(\.profile.userAge) private var userAge: Int = 0
    @AppSetting(\.profile.manualHeight) private var manualHeight: Double = 0

    @Query(sort: \MetricSample.date, order: .reverse) private var samples: [MetricSample]
    @StateObject private var viewModel = BodyModelViewModel()
    @State private var rotationRadians: Double = 0

    private let theme = FeatureTheme.photos

    private var uiTestModeEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestMode")
    }

    private var hasAccess: Bool { premiumStore.isPremium || uiTestModeEnabled }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    if hasAccess {
                        content
                    } else {
                        premiumTeaser
                    }
                }
                .padding(AppSpacing.md)
            }
            .background(AppScreenBackground(tint: theme.softTint))
            .navigationTitle(AppLocalization.string("bodyModel.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: reload)
        .onChange(of: samples.count) { _, _ in reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .needsProfile:
            EmptyStateCard(
                title: AppLocalization.string("bodyModel.empty.profile.title"),
                message: AppLocalization.string("bodyModel.empty.profile.message"),
                systemImage: "person.crop.circle.badge.questionmark",
                actionTitle: AppLocalization.string("bodyModel.empty.profile.action"),
                action: {
                    dismiss()
                    router.selectTab(.settings)
                },
                accessibilityIdentifier: "photos.bodyModel.needsProfile"
            )

        case let .missingMetrics(kinds):
            EmptyStateCard(
                title: AppLocalization.string("bodyModel.empty.metrics.title"),
                message: String(
                    format: AppLocalization.string("bodyModel.empty.metrics.message"),
                    kinds.map(\.title).joined(separator: ", ")
                ),
                systemImage: "ruler",
                actionTitle: AppLocalization.string("bodyModel.empty.metrics.action"),
                action: {
                    dismiss()
                    router.selectTab(.measurements)
                },
                accessibilityIdentifier: "photos.bodyModel.missingMetrics"
            )

        case .single, .comparison:
            mannequinCard
            if case .comparison = viewModel.state { morphControls }
            qualityNote
            changeList
        }
    }

    private var mannequinCard: some View {
        AppGlassCard(cornerRadius: AppRadius.xl, tint: theme.softTint) {
            Group {
                if let parameters = viewModel.currentParameters {
                    MannequinView(parameters: parameters, rotationRadians: rotationRadians)
                        .frame(height: 380)
                        .gesture(
                            DragGesture()
                                .onChanged { rotationRadians = $0.translation.width / 90 }
                        )
                }
            }
            .accessibilityElement()
            .accessibilityLabel(AppLocalization.string("bodyModel.accessibility.mannequin"))
            .accessibilityIdentifier("photos.bodyModel.mannequin")
        }
    }

    private var morphControls: some View {
        AppGlassCard(tint: theme.softTint) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(AppLocalization.string("bodyModel.morph.label"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textSecondary)

                Slider(value: $viewModel.morphProgress, in: 0...1)
                    .tint(theme.accent)
                    .accessibilityIdentifier("photos.bodyModel.morphSlider")

                if AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion) {
                    Button(AppLocalization.string("bodyModel.morph.play")) {
                        Haptics.selection()
                        viewModel.morphProgress = 0
                        withAnimation(.easeInOut(duration: 1.5)) { viewModel.morphProgress = 1 }
                    }
                    .buttonStyle(LiquidCapsuleButtonStyle(tint: theme.accent))
                    .accessibilityIdentifier("photos.bodyModel.play")
                }
            }
        }
    }

    @ViewBuilder
    private var qualityNote: some View {
        if let validation = viewModel.displayedValidation, validation.band != .good {
            AppGlassCard(tint: theme.softTint) {
                HStack(alignment: .top, spacing: AppSpacing.xs) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(theme.accent)
                        .accessibilityHidden(true)
                    Text(qualityMessage(for: validation))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                }
            }
            .accessibilityIdentifier("photos.bodyModel.qualityNote")
        }
    }

    private func qualityMessage(for validation: BodyValidationResult) -> String {
        switch validation.band {
        case .good:
            return ""
        case .approximate:
            return AppLocalization.string("bodyModel.quality.approximate")
        case .suspect:
            return String(
                format: AppLocalization.string("bodyModel.quality.suspect"),
                AppLocalization.string(validation.suspectSite?.localizationKey ?? "")
            )
        }
    }

    @ViewBuilder
    private var changeList: some View {
        if !viewModel.metricChanges.isEmpty {
            AppGlassCard(tint: theme.softTint) {
                VStack(spacing: AppSpacing.xs) {
                    ForEach(viewModel.metricChanges) { change in
                        MetricChangeRow(change: change)
                    }
                }
            }
            .accessibilityIdentifier("photos.bodyModel.changeList")
        }
    }

    private var premiumTeaser: some View {
        EmptyStateCard(
            title: AppLocalization.string("bodyModel.premium.title"),
            message: AppLocalization.string("bodyModel.premium.message"),
            systemImage: "figure.stand",
            actionTitle: AppLocalization.string("bodyModel.premium.action"),
            action: { premiumStore.presentPaywall(reason: .feature("body_model")) },
            accessibilityIdentifier: "photos.bodyModel.premiumTeaser"
        )
    }

    private func reload() {
        viewModel.load(
            samples: samples,
            gender: BodyGender(Gender(rawValue: userGender) ?? .notSpecified),
            age: userAge,
            fallbackHeightCm: manualHeight
        )
    }
}
