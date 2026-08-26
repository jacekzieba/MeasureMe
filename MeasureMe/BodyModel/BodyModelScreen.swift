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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @AppSetting(\.profile.userGender) private var userGender: String = "notSpecified"
    @AppSetting(\.profile.userAge) private var userAge: Int = 0
    @AppSetting(\.profile.manualHeight) private var manualHeight: Double = 0
    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"

    @Query(sort: \MetricSample.date, order: .reverse) private var samples: [MetricSample]
    @StateObject private var viewModel = BodyModelViewModel()
    /// Non-nil while the quick-add sheet is up; carries the metrics it should offer.
    @State private var quickAddRequest: QuickAddRequest?
    /// True while the mesh rig and the solve are still being prepared.
    ///
    /// Starts `true`: `reload()` only raises it inside a `Task`, so with a `false` initial value
    /// the first frame fell through to `loadedContent`, whose default state is `.needsProfile` —
    /// the "complete your profile" card flashed on every entry, which is exactly what the guard
    /// in `content` exists to prevent. `reload()` runs from `.onAppear` and always clears the
    /// flag via `defer`, so nothing can strand it raised.
    @State private var isPreparing = true
    @State private var reloadTask: Task<Void, Never>?

    private let theme = FeatureTheme.photos

    private var hasAccess: Bool { premiumStore.isPremium || UITestArgument.isPresent(.mode) }

    /// The profile's resolved gender, or nil when the user hasn't set one. Computed once so
    /// `reload()` and date-picker selection agree on the same value.
    private var resolvedGender: BodyGender? {
        BodyGender(Gender(rawValue: userGender) ?? .notSpecified)
    }

    /// Newest sample per kind, for prefilling the quick-add sheet. `samples` is already
    /// sorted newest-first, so the first hit for a kind wins.
    private var latestByKind: [MetricKind: (value: Double, date: Date)] {
        var result: [MetricKind: (value: Double, date: Date)] = [:]
        for sample in samples {
            guard let kind = MetricKind(rawValue: sample.kindRaw), result[kind] == nil else { continue }
            result[kind] = (sample.value, sample.date)
        }
        return result
    }

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
            // Without an opaque bar the first card sits under the translucent chrome on entry.
            // Matches SettingsDetailScaffold, which is the app's convention everywhere else.
            .toolbarBackground(AppColorRoles.surfaceChrome, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear(perform: reload)
        .onChange(of: samples.count) { _, _ in reload() }
        .onChange(of: userGender) { _, _ in reload() }
        .sheet(item: $quickAddRequest) { request in
            // No metric this sheet offers depends on the tracked-metrics setting, and
            // switching tabs from behind two stacked sheets would strand the user on
            // whatever screen was left underneath — hide the footer that does that.
            QuickAddSheetView(
                kinds: request.kinds,
                latest: latestByKind,
                unitsSystem: unitsSystem,
                telemetrySource: .bodyModel,
                showsTrackedMetricsFooter: false,
                onSaved: { quickAddRequest = nil }
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        // Replaces the whole content while preparing, rather than only the
        // mannequin: the state defaults to `.needsProfile`, so switching on it
        // first would flash the "complete your profile" card on every entry.
        if isPreparing {
            preparingCard
        } else {
            loadedContent
        }
    }

    /// Matches the mannequin card's height so nothing jumps when it swaps in.
    private var preparingCard: some View {
        AppGlassCard(cornerRadius: AppRadius.xl, tint: theme.softTint) {
            VStack(spacing: AppSpacing.sm) {
                ProgressView()
                    .tint(theme.accent)
                Text(AppLocalization.string("bodyModel.preparing"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 380)
        }
        .accessibilityElement()
        .accessibilityLabel(AppLocalization.string("bodyModel.preparing"))
        .accessibilityIdentifier("photos.bodyModel.preparing")
    }

    @ViewBuilder
    private var loadedContent: some View {
        switch viewModel.state {
        case .needsProfile:
            BodyModelGenderCard(selectedGender: $userGender)

        case let .missingMetrics(kinds):
            BodyModelMissingMetricsCard(
                rows: BodyModelMissingMetrics.rows(for: kinds),
                onAdd: {
                    quickAddRequest = QuickAddRequest(
                        kinds: BodyModelMissingMetrics.quickAddKinds(for: kinds)
                    )
                }
            )

        case .single, .comparison:
            mannequinCard
            if case .comparison = viewModel.state {
                datePickersCard
                morphControls
            }
            qualityNote
            changeList
        }
    }

    /// Lets the user pick which two anchor dates to compare. Hidden in `.single` — there is
    /// nothing to choose between yet.
    @ViewBuilder
    private var datePickersCard: some View {
        if case let .comparison(older, newer) = viewModel.state {
            AppGlassCard(tint: theme.softTint) {
                VStack(spacing: AppSpacing.sm) {
                    datePickerRow(
                        label: AppLocalization.string("bodyModel.dates.older"),
                        selection: older.snapshot.anchorDate,
                        otherSelection: newer.snapshot.anchorDate,
                        isOlderPicker: true,
                        accessibilityIdentifier: "photos.bodyModel.olderDatePicker"
                    )
                    datePickerRow(
                        label: AppLocalization.string("bodyModel.dates.newer"),
                        selection: newer.snapshot.anchorDate,
                        otherSelection: older.snapshot.anchorDate,
                        isOlderPicker: false,
                        accessibilityIdentifier: "photos.bodyModel.newerDatePicker"
                    )
                }
            }
        }
    }

    private func datePickerRow(
        label: String,
        selection: Date,
        otherSelection: Date,
        isOlderPicker: Bool,
        accessibilityIdentifier: String
    ) -> some View {
        let binding = Binding<Date>(
            get: { selection },
            set: { newDate in
                if isOlderPicker {
                    selectDates(olderDate: newDate, newerDate: otherSelection)
                } else {
                    selectDates(olderDate: otherSelection, newerDate: newDate)
                }
            }
        )

        return HStack {
            Text(label)
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(AppColorRoles.textSecondary)
            Spacer()
            Picker(label, selection: binding) {
                ForEach(viewModel.availableDates, id: \.self) { date in
                    Text(date.formatted(date: .abbreviated, time: .omitted)).tag(date)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(theme.accent)
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    /// Re-resolves the comparison for a newly picked pair of dates. Picking the same date
    /// twice, or a "from" that isn't strictly earlier than the "to", is rejected outright —
    /// the picker snaps back to the last valid selection rather than silently reordering the
    /// user's choice into something they didn't ask for.
    private func selectDates(olderDate: Date, newerDate: Date) {
        guard olderDate < newerDate, let gender = resolvedGender else { return }
        reloadTask?.cancel()
        reloadTask = Task {
            isPreparing = true
            defer { isPreparing = false }
            await viewModel.select(
                olderDate: olderDate,
                newerDate: newerDate,
                samples: samples,
                gender: gender,
                age: userAge,
                fallbackHeightCm: manualHeight
            )
        }
    }

    private var mannequinCard: some View {
        AppGlassCard(cornerRadius: AppRadius.xl, tint: theme.softTint) {
            Group {
                if let parameters = viewModel.currentParameters, let gender = resolvedGender {
                    MannequinView(parameters: parameters, gender: gender)
                        .frame(height: 380)
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
            guard let suspectSite = validation.suspectSite else {
                // No single site's deviation cleared the threshold, so no one measurement
                // explains the disagreement — the logged weight is the likelier culprit.
                return AppLocalization.string("bodyModel.quality.suspectNoSite")
            }
            return String(
                format: AppLocalization.string("bodyModel.quality.suspect"),
                AppLocalization.string(suspectSite.localizationKey)
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

    /// Preparing the rig and solving both take real time — measured at roughly
    /// 380 ms on the simulator and more on device, doubled in a comparison — so
    /// this runs as a task and the screen says so meanwhile.
    private func reload() {
        reloadTask?.cancel()
        reloadTask = Task {
            isPreparing = true
            // A stuck spinner is worse than a slow load, so the flag clears on
            // every exit path including cancellation.
            defer { isPreparing = false }
            if let gender = resolvedGender {
                await BodyBaseMeshProvider.prepare(for: gender)
            }
            await viewModel.load(
                samples: samples,
                gender: resolvedGender,
                age: userAge,
                fallbackHeightCm: manualHeight
            )
        }
    }
}

/// Wrapper so the quick-add sheet can be driven by `.sheet(item:)` — the metrics
/// it offers change per presentation, so a plain `isPresented` flag would need a
/// second source of truth for "which ones".
private struct QuickAddRequest: Identifiable {
    let id = UUID()
    let kinds: [MetricKind]
}
