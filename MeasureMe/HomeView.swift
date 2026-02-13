import SwiftUI
import SwiftData

/// HomeView - Ulepszona wersja z mini wykresami i sekcją ostatnich zdjęć
/// 
/// Funkcje:
/// - Maksymalnie 3 kluczowe metryki na Home (z "View more" poniżej)
/// - Nagłówek sekcji "Measurements"
/// - Ulepszone kafelki z mini wykresami sparkline (30 dni)
/// - Sekcja "Last Photos" z maksymalnie 6 ostatnimi zdjęciami (2 rzędy po 3)
/// - Kolorystyka: wzrost = zielony, spadek = czerwony
struct HomeView: View {

    @EnvironmentObject private var metricsStore: ActiveMetricsStore
    @EnvironmentObject private var premiumStore: PremiumStore
    @Environment(\.modelContext) private var modelContext
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("unitsSystem") private var unitsSystem: String = "metric"
    @AppStorage("isSyncEnabled") private var isSyncEnabled: Bool = false
    @AppStorage("showLastPhotosOnHome") private var showLastPhotosOnHome: Bool = true
    @AppStorage("showMeasurementsOnHome") private var showMeasurementsOnHome: Bool = true
    @AppStorage("showHealthMetricsOnHome") private var showHealthMetricsOnHome: Bool = true
    @AppStorage("home_tab_scroll_offset") private var homeTabScrollOffset: Double = 0.0
    @AppStorage("onboarding_skipped_healthkit") private var onboardingSkippedHealthKit: Bool = false
    @AppStorage("onboarding_skipped_reminders") private var onboardingSkippedReminders: Bool = false
    @AppStorage("onboarding_checklist_show") private var showOnboardingChecklistOnHome: Bool = true
    @AppStorage("onboarding_checklist_metrics_completed") private var onboardingChecklistMetricsCompleted: Bool = false
    @AppStorage("onboarding_checklist_premium_explored") private var onboardingChecklistPremiumExplored: Bool = false
    @AppStorage("onboarding_checklist_collapsed") private var onboardingChecklistCollapsed: Bool = false
    @AppStorage("settings_open_tracked_measurements") private var settingsOpenTrackedMeasurements: Bool = false
    @AppStorage("settings_open_reminders") private var settingsOpenReminders: Bool = false
    
    @EnvironmentObject private var router: AppRouter
    
    @Query private var recentSamples: [MetricSample]
    
    @Query private var goals: [MetricGoal]
    
    @Query(sort: [SortDescriptor(\PhotoEntry.date, order: .reverse)])
    private var allPhotos: [PhotoEntry]
    
    @State private var showQuickAddSheet = false
    @State private var selectedPhotoForFullScreen: PhotoEntry?
    @State private var scrollOffset: CGFloat = 0
    @State private var lastPhotosGridWidth: CGFloat = 0
    @State private var checklistStatusText: String?
    @State private var isChecklistConnectingHealth: Bool = false
    @State private var reminderChecklistCompleted: Bool = false
    @State private var showMoreChecklistItems: Bool = false
    
    // HealthKit data
    @State private var latestBodyFat: Double?
    @State private var latestLeanMass: Double?
    @State private var hasAnyMeasurements = false

    // Cached derived data — rebuilt via onChange instead of recomputing on every render
    @State private var cachedSamplesByKind: [MetricKind: [MetricSample]] = [:]
    @State private var cachedLatestByKind: [MetricKind: MetricSample] = [:]
    @State private var cachedGoalsByKind: [MetricKind: MetricGoal] = [:]

    private let maxVisibleMetrics = 3
    private let maxVisiblePhotos = 6

    init() {
        let recentWindowStart = Calendar.current.date(byAdding: .day, value: -120, to: Date()) ?? .distantPast
        _recentSamples = Query(
            filter: #Predicate<MetricSample> { $0.date >= recentWindowStart },
            sort: [SortDescriptor(\.date, order: .reverse)]
        )
    }

    private struct SetupChecklistItem: Identifiable {
        let id: String
        let title: String
        let detail: String
        let icon: String
        let isCompleted: Bool
        let isLoading: Bool
    }
    
    private var lastPhotosGridSide: CGFloat {
        let spacing: CGFloat = 8
        let totalSpacing = spacing * 2
        guard lastPhotosGridWidth.isFinite, lastPhotosGridWidth > 0 else { return 86 }
        let raw = (lastPhotosGridWidth - totalSpacing) / 3
        guard raw.isFinite, raw > 0 else { return 86 }
        return max(floor(raw), 86)
    }

    
    /// Widoczne metryki (maksymalnie 3)
    private var visibleMetrics: [MetricKind] {
        Array(metricsStore.keyMetrics.prefix(maxVisibleMetrics))
    }
    
    
    /// Widoczne zdjęcia (maksymalnie 6)
    private var visiblePhotos: [PhotoEntry] {
        Array(allPhotos.prefix(maxVisiblePhotos))
    }
    
    /// Słownik próbek dla każdego rodzaju metryki
    private func samplesForKind(_ kind: MetricKind) -> [MetricSample] {
        cachedSamplesByKind[kind] ?? []
    }
    
    /// Najnowsze pomiary dla wskaźników zdrowotnych
    private var latestWaist: Double? {
        cachedLatestByKind[.waist]?.value
    }

    private var latestHeight: Double? {
        cachedLatestByKind[.height]?.value
    }

    private var latestWeight: Double? {
        cachedLatestByKind[.weight]?.value
    }

    // MARK: - Cache Rebuild Helpers

    private var recentSamplesSignature: Int {
        var hasher = Hasher()
        for sample in recentSamples {
            hasher.combine(sample.persistentModelID)
            hasher.combine(sample.value.bitPattern)
            hasher.combine(sample.date.timeIntervalSinceReferenceDate)
        }
        return hasher.finalize()
    }

    /// Rebuilds samplesByKind from the recent @Query window.
    private func rebuildSamplesCache() {
        var grouped: [MetricKind: [MetricSample]] = [:]
        for sample in recentSamples {
            guard let kind = MetricKind(rawValue: sample.kindRaw) else {
                AppLog.debug("⚠️ Ignoring MetricSample with invalid kindRaw: \(sample.kindRaw)")
                continue
            }
            grouped[kind, default: []].append(sample)
        }
        cachedSamplesByKind = grouped
    }

    private func refreshLatestSamplesCache() {
        var latest: [MetricKind: MetricSample] = [:]
        let kindsToFetch = Set(metricsStore.activeKinds).union([.waist, .height, .weight, .bodyFat, .leanBodyMass])
        for kind in kindsToFetch {
            let kindValue = kind.rawValue
            var descriptor = FetchDescriptor<MetricSample>(
                predicate: #Predicate { $0.kindRaw == kindValue },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            if let sample = try? modelContext.fetch(descriptor).first {
                latest[kind] = sample
            }
        }
        cachedLatestByKind = latest
    }

    private func refreshHasAnyMeasurements() {
        let descriptor = FetchDescriptor<MetricSample>()
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        hasAnyMeasurements = count > 0
    }

    private func refreshMeasurementCaches() {
        rebuildSamplesCache()
        refreshLatestSamplesCache()
        refreshHasAnyMeasurements()
        autoHideChecklistIfCompleted()
    }
    
    /// Synchronizes Measurement samples with metric snapshots stored on photos.
    /// - Behavior:
    ///   - For each PhotoEntry, for each MetricValueSnapshot, ensure a MetricSample exists on the snapshot's date.
    ///   - If a sample for (kind,date) exists, update its value to the snapshot's value.
    ///   - If none exists, insert a new MetricSample.
    ///   - Never delete MetricSample when a photo is deleted; this function only upserts.
    private func syncMeasurementsFromPhotosIfNeeded() {
        // Build a cache of existing samples by (kindRaw, dayStart)
        var existingByKey: [String: MetricSample] = [:]
        do {
            // Fetch a wide window to avoid excessive fetching; adjust if needed
            let descriptor = FetchDescriptor<MetricSample>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            let existing = try modelContext.fetch(descriptor)
            let cal = Calendar.current
            for s in existing {
                let startOfDay = cal.startOfDay(for: s.date)
                let key = "\(s.kindRaw)|\(startOfDay.timeIntervalSince1970)"
                if existingByKey[key] == nil { existingByKey[key] = s }
            }
        } catch {
            AppLog.debug("⚠️ Failed to build existing samples index: \(error)")
        }

        // Iterate photos and upsert samples for each snapshot
        for photo in allPhotos {
            let photoDate = photo.date
            let dayStart = Calendar.current.startOfDay(for: photoDate)
            for snapshot in photo.linkedMetrics {
                guard let kind = snapshot.kind else { continue }
                let kindRaw = kind.rawValue
                let key = "\(kindRaw)|\(dayStart.timeIntervalSince1970)"
                if let sample = existingByKey[key] {
                    // Update existing sample to snapshot value and photo date (exact time)
                    sample.value = snapshot.value
                    sample.date = photoDate
                } else {
                    let sample = MetricSample(kind: kind, value: snapshot.value, date: photoDate)
                    modelContext.insert(sample)
                    existingByKey[key] = sample
                }
            }
        }

        // No deletes here on purpose (photo deletions should not remove samples)
    }

    /// Rebuilds goalsByKind from the @Query goals array.
    private func rebuildGoalsCache() {
        var dict: [MetricKind: MetricGoal] = [:]
        for goal in goals {
            if let kind = MetricKind(rawValue: goal.kindRaw) {
                dict[kind] = goal
            }
        }
        cachedGoalsByKind = dict
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(
                topHeight: 380,
                scrollOffset: scrollOffset,
                tint: Color.cyan.opacity(0.22)
            )

            // Zawartość przewijalna
            ScrollView {
                VStack(spacing: 22) {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: HomeScrollOffsetKey.self,
                                value: proxy.frame(in: .named("homeScroll")).minY
                            )
                    }
                    .frame(height: 0)

                    greetingCard

                    if showOnboardingChecklistOnHome && !activeChecklistItems.isEmpty {
                        setupChecklistSection
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                    }

                    // SEKCJA: MEASUREMENTS
                    if showMeasurementsOnHome {
                        measurementsSection
                    }
                    
                    // SEKCJA: LAST PHOTOS
                    if showLastPhotosOnHome {
                        if allPhotos.isEmpty {
                            lastPhotosEmptyState
                        } else {
                            lastPhotosSection
                        }
                    }
                    
                    // SEKCJA: HEALTH
                    if showHealthMetricsOnHome, premiumStore.isPremium {
                        AppGlassCard(
                            depth: .base,
                            cornerRadius: 24,
                            tint: Color.cyan.opacity(0.16),
                            contentPadding: 12
                        ) {
                            HealthMetricsSection(
                                latestWaist: latestWaist,
                                latestHeight: latestHeight,
                                latestWeight: latestWeight,
                                latestBodyFat: latestBodyFat,
                                latestLeanMass: latestLeanMass,
                                displayMode: .summaryOnly,
                                title: "Health"
                            )
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .coordinateSpace(name: "homeScroll")
            .onPreferenceChange(HomeScrollOffsetKey.self) { value in
                scrollOffset = value
                homeTabScrollOffset = Double(value)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(scrollOffset < -16 ? .visible : .hidden, for: .navigationBar)
        .sheet(isPresented: $showQuickAddSheet) {
            QuickAddSheetView(
                kinds: metricsStore.activeKinds,
                latest: Dictionary(
                    uniqueKeysWithValues: cachedLatestByKind.map { ($0.key, ($0.value.value, $0.value.date)) }
                ),
                unitsSystem: unitsSystem
            ) {
                showQuickAddSheet = false
            }
        }
        .sheet(item: $selectedPhotoForFullScreen) { photo in
            PhotoDetailView(photo: photo)
        }
        .onAppear {
            refreshMeasurementCaches()
            rebuildGoalsCache()
            fetchHealthKitData()
            refreshChecklistState()
            syncMeasurementsFromPhotosIfNeeded()
        }
        .onChange(of: recentSamplesSignature) { _, _ in
            refreshMeasurementCaches()
        }
        .onChange(of: metricsStore.activeKinds) { _, _ in
            refreshMeasurementCaches()
        }
        .onChange(of: goals.count) { _, _ in
            rebuildGoalsCache()
        }
        .onChange(of: isSyncEnabled) { _, _ in
            refreshChecklistState()
        }
        .onChange(of: allPhotos.count) { _, _ in
            refreshChecklistState()
            syncMeasurementsFromPhotosIfNeeded()
        }
        .onChange(of: onboardingChecklistMetricsCompleted) { _, _ in
            refreshChecklistState()
        }
        .onChange(of: onboardingChecklistPremiumExplored) { _, _ in
            refreshChecklistState()
        }
        .onChange(of: onboardingSkippedHealthKit) { _, _ in
            refreshChecklistState()
        }
        .onChange(of: onboardingSkippedReminders) { _, _ in
            refreshChecklistState()
        }
    }
    
    // MARK: - HealthKit Data Fetching
    
    private func fetchHealthKitData() {
        guard isSyncEnabled else {
            latestBodyFat = nil
            latestLeanMass = nil
            return
        }

        Task {
            do {
                let composition = try await HealthKitManager.shared.fetchLatestBodyCompositionCached()
                await MainActor.run {
                    // Keep values truthful: no fake placeholders if Health data is missing.
                    latestBodyFat = composition.bodyFat
                    latestLeanMass = composition.leanMass
                }
            } catch {
                AppLog.debug("⚠️ Error fetching HealthKit data: \(error.localizedDescription)")
                await MainActor.run {
                    latestBodyFat = nil
                    latestLeanMass = nil
                }
            }
        }
    }

    private var greetingCard: some View {
        return AppGlassCard(
            depth: .floating,
            cornerRadius: 24,
            tint: Color.appAccent.opacity(0.26),
            contentPadding: 16
        ) {
            VStack(alignment: .leading, spacing: hasAnyMeasurements ? 10 : 8) {
                HStack(spacing: 10) {
                    Image("BrandButton")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                    Text("MeasureMe")
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                }

                Text(greetingTitle)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)

                if hasAnyMeasurements {
                    Text(encouragementText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }

                if goalStatus != .noGoals {
                    Text(goalStatusText)
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(Color.white.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var checklistItems: [SetupChecklistItem] {
        var items: [SetupChecklistItem] = [
            SetupChecklistItem(
                id: "first_measurement",
                title: AppLocalization.string("First measurement"),
                detail: AppLocalization.string("Start your trend with one quick check-in."),
                icon: "ruler.fill",
                isCompleted: hasAnyMeasurements,
                isLoading: false
            ),
            SetupChecklistItem(
                id: "first_photo",
                title: AppLocalization.string("First Photo"),
                detail: AppLocalization.string("Photos make progress easier to notice."),
                icon: "camera.fill",
                isCompleted: !allPhotos.isEmpty,
                isLoading: false
            )
        ]

        items.append(
            SetupChecklistItem(
                id: "healthkit",
                title: AppLocalization.string("Connect Apple Health"),
                detail: AppLocalization.string("Import history and keep data in sync."),
                icon: "heart.text.square",
                isCompleted: isSyncEnabled,
                isLoading: isChecklistConnectingHealth
            )
        )

        items.append(
            SetupChecklistItem(
                id: "choose_metrics",
                title: AppLocalization.string("Choose metrics"),
                detail: AppLocalization.string("Track only what matters to you."),
                icon: "slider.horizontal.3",
                isCompleted: onboardingChecklistMetricsCompleted,
                isLoading: false
            )
        )

        if onboardingSkippedReminders {
            items.append(
                SetupChecklistItem(
                    id: "reminders",
                    title: AppLocalization.string("Set reminders"),
                    detail: AppLocalization.string("One weekly nudge helps keep the habit."),
                    icon: "bell.badge",
                    isCompleted: reminderChecklistCompleted,
                    isLoading: false
                )
            )
        }

        items.append(
            SetupChecklistItem(
                id: "premium",
                title: AppLocalization.string("Explore Premium"),
                detail: AppLocalization.string("Try deeper insights and compare photos side-by-side."),
                icon: "sparkles",
                isCompleted: onboardingChecklistPremiumExplored || premiumStore.isPremium,
                isLoading: false
            )
        )

        return items
    }

    private var activeChecklistItems: [SetupChecklistItem] {
        checklistItems.filter { !$0.isCompleted }
    }

    private var allChecklistItemsCompleted: Bool {
        !checklistItems.isEmpty && checklistItems.allSatisfy(\.isCompleted)
    }

    private var primaryChecklistIDs: [String] {
        ["first_measurement", "first_photo", "healthkit"]
    }

    private var primaryChecklistItems: [SetupChecklistItem] {
        activeChecklistItems.filter { primaryChecklistIDs.contains($0.id) }
    }

    private var secondaryChecklistItems: [SetupChecklistItem] {
        activeChecklistItems.filter { !primaryChecklistIDs.contains($0.id) }
    }

    private var shownChecklistItems: [SetupChecklistItem] {
        if showMoreChecklistItems {
            return primaryChecklistItems + secondaryChecklistItems
        }
        return primaryChecklistItems
    }

    private var setupChecklistSection: some View {
        AppGlassCard(
            depth: .base,
            cornerRadius: 24,
            tint: Color.appAccent.opacity(0.16),
            contentPadding: 16
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppLocalization.string("Finish setup"))
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Menu {
                        Button(AppLocalization.string("Hide checklist")) {
                            Haptics.selection()
                            showOnboardingChecklistOnHome = false
                        }
                        Button(onboardingChecklistCollapsed ? AppLocalization.string("Expand checklist") : AppLocalization.string("Collapse checklist")) {
                            Haptics.selection()
                            onboardingChecklistCollapsed.toggle()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(AppLocalization.string("accessibility.setup.checklist.options"))
                    .accessibilityHint(AppLocalization.string("accessibility.setup.checklist.options.hint"))
                }

                if onboardingChecklistCollapsed {
                    Text(AppLocalization.string("Checklist collapsed. Open menu to expand."))
                        .font(AppTypography.caption)
                        .foregroundStyle(.white.opacity(0.72))
                } else {
                    ForEach(shownChecklistItems) { item in
                        Button {
                            performChecklistAction(item.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(item.isCompleted ? Color(hex: "#22C55E") : Color.appAccent)
                                    .frame(width: 28, height: 28)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(AppTypography.bodyEmphasis)
                                        .foregroundStyle(.white)
                                    Text(item.detail)
                                        .font(AppTypography.micro)
                                        .foregroundStyle(.white.opacity(0.68))
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 10)

                                if item.isLoading {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(Color.appAccent)
                                } else if item.isCompleted {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(Color(hex: "#22C55E"))
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.45))
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(item.isLoading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.title). \(item.detail)")
                        .accessibilityValue(
                            item.isLoading
                            ? AppLocalization.string("accessibility.setup.checklist.loading")
                            : (item.isCompleted
                               ? AppLocalization.string("accessibility.setup.checklist.completed")
                               : AppLocalization.string("accessibility.setup.checklist.incomplete"))
                        )
                    }

                    if !showMoreChecklistItems, secondaryChecklistItems.count >= 3 {
                        Button {
                            Haptics.selection()
                            showMoreChecklistItems = true
                        } label: {
                            Text(AppLocalization.string("Show %d more", 3))
                                .font(AppTypography.captionEmphasis)
                                .foregroundStyle(Color.appAccent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let checklistStatusText {
                    Text(checklistStatusText)
                        .font(AppTypography.micro)
                        .foregroundStyle(Color.appAccent)
                }
            }
        }
    }

    private var trimmedUserName: String {
        userName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum DayPart {
        case morning
        case afternoon
        case evening
    }

    private var dayPart: DayPart {
        let hour = Calendar.current.component(.hour, from: .now)
        if hour < 12 { return .morning }
        if hour < 18 { return .afternoon }
        return .evening
    }

    private var greetingTitle: String {
        let name = trimmedUserName
        switch dayPart {
        case .morning:
            return name.isEmpty
                ? AppLocalization.string("home.greeting.morning")
                : AppLocalization.string("home.greeting.morning.named", name)
        case .afternoon:
            return name.isEmpty
                ? AppLocalization.string("home.greeting.afternoon")
                : AppLocalization.string("home.greeting.afternoon.named", name)
        case .evening:
            return name.isEmpty
                ? AppLocalization.string("home.greeting.evening")
                : AppLocalization.string("home.greeting.evening.named", name)
        }
    }

    private var encouragementText: String {
        AppLocalization.string("home.encouragement")
    }

    private enum GoalStatusLevel {
        case onTrack
        case slightlyOff
        case needsAttention
        case noGoals
    }

    private var goalStatus: GoalStatusLevel {
        let statuses: [GoalStatusLevel] = visibleMetrics.compactMap { kind in
            guard let goal = cachedGoalsByKind[kind], let latest = cachedLatestByKind[kind] else { return nil }
            if goal.isAchieved(currentValue: latest.value) { return .onTrack }
            let remaining = abs(goal.remainingToGoal(currentValue: latest.value))
            let target = max(abs(goal.targetValue), 0.0001)
            let ratio = remaining / target
            return ratio <= 0.10 ? .slightlyOff : .needsAttention
        }

        if statuses.isEmpty { return .noGoals }
        if statuses.contains(.needsAttention) { return .needsAttention }
        if statuses.contains(.slightlyOff) { return .slightlyOff }
        return .onTrack
    }

    private var goalStatusText: String {
        switch goalStatus {
        case .onTrack: return AppLocalization.string("home.goalstatus.ontrack")
        case .slightlyOff: return AppLocalization.string("home.goalstatus.slightlyoff")
        case .needsAttention: return AppLocalization.string("home.goalstatus.needsattention")
        case .noGoals: return AppLocalization.string("home.goalstatus.nogoals")
        }
    }

    private func homeMetricAccessibilityLabel(kind: MetricKind) -> String {
        if let latest = cachedLatestByKind[kind] {
            let shown = kind.valueForDisplay(fromMetric: latest.value, unitsSystem: unitsSystem)
            let unit = kind.unitSymbol(unitsSystem: unitsSystem)
            let valueText = String(format: "%.1f %@", shown, unit)
            return AppLocalization.string("home.metric.accessibility.value", kind.title, valueText)
        }
        return AppLocalization.string("home.metric.accessibility.nodata", kind.title)
    }

    private func refreshChecklistState() {
        let reminders = NotificationManager.shared.loadReminders()
        reminderChecklistCompleted = NotificationManager.shared.notificationsEnabled && !reminders.isEmpty
        autoHideChecklistIfCompleted()
    }

    private func autoHideChecklistIfCompleted() {
        guard allChecklistItemsCompleted, showOnboardingChecklistOnHome else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.4)) {
                showOnboardingChecklistOnHome = false
            }
        }
    }

    private func performChecklistAction(_ id: String) {
        switch id {
        case "first_measurement":
            Haptics.selection()
            showQuickAddSheet = true
        case "first_photo":
            Haptics.selection()
            router.selectedTab = .photos
        case "choose_metrics":
            Haptics.selection()
            onboardingChecklistMetricsCompleted = true
            settingsOpenTrackedMeasurements = true
            router.selectedTab = .settings
        case "reminders":
            Haptics.selection()
            settingsOpenReminders = true
            router.selectedTab = .settings
        case "healthkit":
            connectHealthKitFromChecklist()
        case "premium":
            Haptics.light()
            onboardingChecklistPremiumExplored = true
            premiumStore.presentPaywall(reason: .onboarding)
        default:
            break
        }
    }

    private func connectHealthKitFromChecklist() {
        guard !isSyncEnabled, !isChecklistConnectingHealth else { return }

        checklistStatusText = AppLocalization.string("Requesting Health access...")
        isChecklistConnectingHealth = true

        Task { @MainActor in
            defer { isChecklistConnectingHealth = false }
            do {
                try await HealthKitManager.shared.requestAuthorization()
                isSyncEnabled = true
                onboardingSkippedHealthKit = true
                checklistStatusText = AppLocalization.string("Connected to Apple Health.")
                Haptics.success()
                refreshChecklistState()
            } catch {
                isSyncEnabled = false
                checklistStatusText = AppLocalization.string("Health access denied. You can enable it later in Settings.")
                if let authError = error as? HealthKitAuthorizationError {
                    checklistStatusText = authError.errorDescription ?? checklistStatusText
                }
                Haptics.error()
            }
        }
    }
    
    // MARK: - Measurements Section
    
    private var measurementsSection: some View {
        AppGlassCard(
            depth: .elevated,
            cornerRadius: 24,
            tint: Color.appAccent.opacity(0.18),
            contentPadding: 16
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text(AppLocalization.string("Measurements"))
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(.white)

                if !hasAnyMeasurements {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(AppLocalization.string("No measurements yet."))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)

                        Text(AppLocalization.string("Add your first measurement to unlock trends and goal progress."))
                            .font(AppTypography.body)
                            .foregroundStyle(.white.opacity(0.7))

                        Button {
                            showQuickAddSheet = true
                        } label: {
                            Text(AppLocalization.string("Add measurement"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.appAccent)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                if visibleMetrics.isEmpty {
                    Text(AppLocalization.string("Select up to three key metrics in Settings."))
                        .font(AppTypography.body)
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    VStack(spacing: 12) {
                        ForEach(visibleMetrics, id: \.self) { kind in
                            NavigationLink {
                                MetricDetailView(kind: kind)
                            } label: {
                                HomeKeyMetricRow(
                                    kind: kind,
                                    latest: cachedLatestByKind[kind],
                                    goal: cachedGoalsByKind[kind],
                                    samples: samplesForKind(kind),
                                    unitsSystem: unitsSystem
                                )
                            }
                            .buttonStyle(PressableTileStyle())
                            .accessibilityLabel(homeMetricAccessibilityLabel(kind: kind))
                            .accessibilityHint(AppLocalization.string("accessibility.opens.details", kind.title))
                        }
                    }
                }

                Button {
                    router.selectedTab = .measurements
                } label: {
                    HStack(spacing: 6) {
                        Text(AppLocalization.string("View more"))
                            .font(AppTypography.sectionAction)
                        Image(systemName: "chevron.right")
                            .font(AppTypography.micro)
                    }
                    .foregroundStyle(Color(hex: "#FCA311"))
                }
                .buttonStyle(LiquidCapsuleButtonStyle(tint: Color.appAccent.opacity(0.88)))
                .accessibilityLabel(AppLocalization.string("accessibility.open.measurements"))
                .accessibilityHint(AppLocalization.string("accessibility.opens.measurements"))
            }
        }
    }
    
    // MARK: - Last Photos Section
    
    private var lastPhotosSection: some View {
        AppGlassCard(
            depth: .elevated,
            cornerRadius: 24,
            tint: Color.cyan.opacity(0.14),
            contentPadding: 16
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // Nagłówek sekcji
                HStack {
                    Text(AppLocalization.string("Last Photos"))
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    if allPhotos.count > maxVisiblePhotos {
                        Button {
                            router.selectedTab = .photos
                        } label: {
                            HStack(spacing: 4) {
                                Text(AppLocalization.string("View All"))
                                    .font(AppTypography.sectionAction)
                                Image(systemName: "chevron.right")
                                    .font(AppTypography.micro)
                            }
                            .foregroundStyle(Color(hex: "#FCA311"))
                        }
                        .buttonStyle(LiquidCapsuleButtonStyle(tint: Color.cyan.opacity(0.72)))
                        .accessibilityLabel(AppLocalization.string("accessibility.open.photos"))
                        .accessibilityHint(AppLocalization.string("accessibility.opens.photos"))
                    }
                }
                
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(lastPhotosGridSide), spacing: 8), count: 3),
                    spacing: 8
                ) {
                    ForEach(visiblePhotos) { photo in
                        Button {
                            selectedPhotoForFullScreen = photo
                        } label: {
                            PhotoGridThumb(
                                imageData: photo.imageData,
                                size: lastPhotosGridSide,
                                cacheID: String(describing: photo.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AppLocalization.string("accessibility.open.photo.details"))
                        .accessibilityValue(photo.date.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                .frame(height: {
                    let rows = max(1, Int(ceil(Double(visiblePhotos.count) / 3.0)))
                    let spacing: CGFloat = 8
                    return CGFloat(rows) * lastPhotosGridSide + CGFloat(max(rows - 1, 0)) * spacing
                }())
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                let width = geo.size.width
                                if width.isFinite, width > 0 {
                                    lastPhotosGridWidth = width
                                }
                            }
                            .onChange(of: geo.size.width) { _, newValue in
                                if newValue.isFinite, newValue > 0 {
                                    lastPhotosGridWidth = newValue
                                }
                            }
                    }
                )
            }
        }
    }

    private var lastPhotosEmptyState: some View {
        AppGlassCard(
            depth: .elevated,
            cornerRadius: 24,
            tint: Color.cyan.opacity(0.14),
            contentPadding: 16
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(AppLocalization.string("Last Photos"))
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(.white)

                Text(AppLocalization.string("No photos yet. Capture progress photos to see changes beyond the scale."))
                    .font(AppTypography.body)
                    .foregroundStyle(.white.opacity(0.7))

                Button {
                    router.selectedTab = .photos
                } label: {
                    Text(AppLocalization.string("Add photo"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.appAccent)
            }
        }
    }
}

private struct PhotoGridThumb: View {
    let imageData: Data
    let size: CGFloat
    let cacheID: String
    
    var body: some View {
        DownsampledImageView(
            imageData: imageData,
            targetSize: CGSize(width: size, height: size),
            contentMode: .fill,
            cornerRadius: 12,
            showsProgress: false,
            cacheID: cacheID
        )
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Home Key Metric Row

struct HomeKeyMetricRow: View {
    let kind: MetricKind
    let latest: MetricSample?
    let goal: MetricGoal?
    let samples: [MetricSample]
    let unitsSystem: String

    private let cornerRadius: CGFloat = 16

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: kind.systemImage)
                        .font(AppTypography.metricTitle)
                        .foregroundStyle(Color(hex: "#FCA311"))
                        .scaleEffect(x: kind.shouldMirrorSymbol ? -1 : 1, y: 1)
                        .frame(width: 16, height: 16)

                    ViewThatFits(in: .vertical) {
                        Text(kind.title)
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(kind.title)
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let latest {
                    Text(valueString(metricValue: latest.value))
                        .font(AppTypography.metricValue)
                        .foregroundStyle(.white)

                    if let goal = goal {
                        HomeGoalProgressBar(
                            goal: goal,
                            latest: latest,
                            baselineValue: baselineValue(for: goal),
                            format: { valueString(metricValue: $0) }
                        )
                    } else {
                        Text(AppLocalization.string("Set a goal to see progress."))
                            .font(AppTypography.micro)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    Text(AppLocalization.string("—"))
                        .font(AppTypography.metricValue)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(AppLocalization.string("No data yet"))
                        .font(AppTypography.micro)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Spacer(minLength: 8)

            if !samples.isEmpty {
                MiniSparklineChart(samples: samples, kind: kind, goal: goal)
                    .frame(width: 90, height: 44)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 90, height: 44)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppGlassBackground(
                depth: .base,
                cornerRadius: cornerRadius,
                tint: Color.appAccent.opacity(0.10)
            )
        )
    }

    private func valueString(metricValue: Double) -> String {
        let shown = kind.valueForDisplay(fromMetric: metricValue, unitsSystem: unitsSystem)
        let unit = kind.unitSymbol(unitsSystem: unitsSystem)
        return String(format: "%.1f %@", shown, unit)
    }

    private func baselineValue(for goal: MetricGoal) -> Double {
        guard !samples.isEmpty else { return latest?.value ?? goal.targetValue }
        let sorted = samples.sorted { $0.date < $1.date }
        if let baseline = sorted.last(where: { $0.date <= goal.createdDate }) {
            return baseline.value
        }
        return sorted.first?.value ?? (latest?.value ?? goal.targetValue)
    }
}

private struct HomeGoalProgressBar: View {
    let goal: MetricGoal
    let latest: MetricSample
    let baselineValue: Double
    let format: (Double) -> String

    var body: some View {
        let currentVal = latest.value
        let goalVal = goal.targetValue
        let isAchieved = goal.isAchieved(currentValue: currentVal)
        let progress: Double
        switch goal.direction {
        case .increase:
            let denominator = goalVal - baselineValue
            let raw = denominator == 0 ? (isAchieved ? 1.0 : 0.0) : (currentVal - baselineValue) / denominator
            progress = min(max(raw, 0.0), 1.0)
        case .decrease:
            let denominator = baselineValue - goalVal
            let raw = denominator == 0 ? (isAchieved ? 1.0 : 0.0) : (baselineValue - currentVal) / denominator
            progress = min(max(raw, 0.0), 1.0)
        }

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(AppLocalization.string("Progress"))
                    .font(AppTypography.micro)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(AppTypography.microEmphasis.monospacedDigit())
                    .foregroundStyle(isAchieved ? Color(hex: "#22C55E") : Color(hex: "#FCA311"))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(isAchieved ? Color(hex: "#22C55E") : Color(hex: "#FCA311"))
                        .frame(width: geo.size.width * max(0, min(1, progress)))
                }
            }
            .frame(height: 6)

            HStack {
                Text(AppLocalization.string("progress.now", format(currentVal)))
                    .font(AppTypography.micro)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(AppLocalization.string("progress.goal", format(goalVal)))
                    .font(AppTypography.micro)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}
// MARK: - Button Style

private struct PressableTileStyle: ButtonStyle {
    @AppStorage("animationsEnabled") private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let shouldAnimate = animationsEnabled && !reduceMotion
        configuration.label
            .scaleEffect(configuration.isPressed && shouldAnimate ? 0.98 : 1)
            .opacity(configuration.isPressed && shouldAnimate ? 0.9 : 1)
    }
}

private struct HomeScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

