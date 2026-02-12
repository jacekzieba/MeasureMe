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
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("unitsSystem") private var unitsSystem: String = "metric"
    @AppStorage("showLastPhotosOnHome") private var showLastPhotosOnHome: Bool = true
    @AppStorage("showMeasurementsOnHome") private var showMeasurementsOnHome: Bool = true
    @AppStorage("showHealthMetricsOnHome") private var showHealthMetricsOnHome: Bool = true
    @AppStorage("home_tab_scroll_offset") private var homeTabScrollOffset: Double = 0.0
    
    @Environment(AppRouter.self) private var router
    
    @Query(sort: [SortDescriptor(\MetricSample.date, order: .reverse)])
    private var samples: [MetricSample]
    
    @Query private var goals: [MetricGoal]
    
    @Query(sort: [SortDescriptor(\PhotoEntry.date, order: .reverse)])
    private var allPhotos: [PhotoEntry]
    
    @State private var showQuickAddSheet = false
    @State private var selectedPhotoForFullScreen: PhotoEntry?
    @State private var scrollOffset: CGFloat = 0
    @State private var lastPhotosGridWidth: CGFloat = 0
    
    // HealthKit data
    @State private var latestBodyFat: Double?
    @State private var latestLeanMass: Double?
    
    private let maxVisibleMetrics = 3
    private let maxVisiblePhotos = 6
    
    private var lastPhotosGridSide: CGFloat {
        let spacing: CGFloat = 8
        let totalSpacing = spacing * 2
        let width = lastPhotosGridWidth > 0 ? lastPhotosGridWidth : 0
        let raw = (width - totalSpacing) / 3
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
        samplesByKind[kind] ?? []
    }
    
    /// Najnowsze pomiary dla wskaźników zdrowotnych
    private var latestWaist: Double? {
        latestByKind[.waist]?.value
    }
    
    private var latestHeight: Double? {
        latestByKind[.height]?.value
    }
    
    private var latestWeight: Double? {
        latestByKind[.weight]?.value
    }

    /// Próbki pogrupowane per metryka (malejąco po dacie - zgodnie z @Query)
    private var samplesByKind: [MetricKind: [MetricSample]] {
        var grouped: [MetricKind: [MetricSample]] = [:]
        for sample in samples {
            guard let kind = MetricKind(rawValue: sample.kindRaw) else { continue }
            grouped[kind, default: []].append(sample)
        }
        return grouped
    }
    
    /// Najnowsza próbka dla każdego rodzaju
    private var latestByKind: [MetricKind: MetricSample] {
        var latest: [MetricKind: MetricSample] = [:]
        for (kind, list) in samplesByKind {
            if let first = list.first {
                latest[kind] = first
            }
        }
        return latest
    }
    
    /// Cele dla każdego rodzaju
    private var goalsByKind: [MetricKind: MetricGoal] {
        var dict: [MetricKind: MetricGoal] = [:]
        for goal in goals {
            if let kind = MetricKind(rawValue: goal.kindRaw) {
                dict[kind] = goal
            }
        }
        return dict
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
                    uniqueKeysWithValues: latestByKind.map { ($0.key, ($0.value.value, $0.value.date)) }
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
            fetchHealthKitData()
        }
    }
    
    // MARK: - HealthKit Data Fetching
    
    private func fetchHealthKitData() {
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
            VStack(alignment: .leading, spacing: 10) {
                Text(greetingTitle)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)

                Text(encouragementText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))

                Text(goalStatusText)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(Color.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
            guard let goal = goalsByKind[kind], let latest = latestByKind[kind] else { return nil }
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
        if let latest = latestByKind[kind] {
            let shown = kind.valueForDisplay(fromMetric: latest.value, unitsSystem: unitsSystem)
            let unit = kind.unitSymbol(unitsSystem: unitsSystem)
            let valueText = String(format: "%.1f %@", shown, unit)
            return AppLocalization.string("home.metric.accessibility.value", kind.title, valueText)
        }
        return AppLocalization.string("home.metric.accessibility.nodata", kind.title)
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

                if samples.isEmpty {
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
                                    latest: latestByKind[kind],
                                    goal: goalsByKind[kind],
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
                            .onAppear { lastPhotosGridWidth = geo.size.width }
                            .onChange(of: geo.size.width) { _, newValue in
                                lastPhotosGridWidth = newValue
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

                    Text(kind.title)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
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
