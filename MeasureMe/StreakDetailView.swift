import SwiftData
import SwiftUI

// MARK: - StreakDetailView

struct StreakDetailView: View {
    @ObservedObject var streakManager: StreakManager
    @State var viewModel = StreakDetailViewModel()

    @Query var thisWeekSamples: [MetricSample]
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    // Binding-required state (must stay in View)
    @State var showAllLogs = false
    @State var vacationEndSelection: Date = AppClock.now

    @AppSetting(\.experience.animationsEnabled) var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    // MARK: - Adaptive colors
    var streakText: Color { colorScheme == .dark ? .white : AppColorRoles.textPrimary }
    var streakTextSecondary: Color { colorScheme == .dark ? .white.opacity(0.55) : AppColorRoles.textSecondary }
    var streakTextTertiary: Color { colorScheme == .dark ? .white.opacity(0.45) : AppColorRoles.textTertiary }
    var streakDivider: Color { colorScheme == .dark ? .white.opacity(0.16) : AppColorRoles.borderSubtle }
    var streakMuted: Color { colorScheme == .dark ? .white.opacity(0.07) : AppColorRoles.surfaceSecondary }
    var streakSubtle: Color { colorScheme == .dark ? .white.opacity(0.35) : AppColorRoles.textTertiary }

    var shouldAnimate: Bool {
        animationsEnabled && !reduceMotion
    }

    // MARK: - Init

    init(streakManager: StreakManager) {
        self._streakManager = ObservedObject(wrappedValue: streakManager)
        let calendar = Calendar(identifier: .iso8601)
        let now = AppClock.now
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? now
        _thisWeekSamples = Query(
            filter: #Predicate<MetricSample> { $0.date >= weekStart && $0.date < weekEnd },
            sort: [SortDescriptor(\.date, order: .forward)]
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                if colorScheme == .dark {
                    Color.black.ignoresSafeArea()
                } else {
                    AppScreenBackground(tint: Color.orange.opacity(0.18))
                }

                ScrollView {
                    VStack(spacing: 28) {
                        flameSection
                        statsSection
                        thisWeekSection
                        if viewModel.selectedYear > 0 {
                            activityHeatmapSection
                        }
                        milestoneSection
                        totalLogsRow
                        motivationalCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }

                headerBar
            }
            .navigationDestination(isPresented: $showAllLogs) {
                AllLogsView()
            }
            .onAppear {
                handleStreakDetailAppear()
            }
            .onChange(of: streakManager.isVacationModeActive) { _, _ in
                handleVacationStateChange()
            }
            .onChange(of: streakManager.vacationWeeksRemaining) { _, _ in
                handleVacationStateChange()
            }
        }
    }

    // MARK: - Header

    var headerBar: some View {
        HStack {
            Button(action: dismissStreakDetail) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(streakText)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(colorScheme == .dark ? .white.opacity(0.12) : AppColorRoles.surfaceGlass))
            }
            .buttonStyle(.plain)
            .appHitTarget()

            Spacer()

            Text(AppLocalization.string("streak.detail.title"))
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(streakTextSecondary)
                .tracking(2)
                .textCase(.uppercase)

            Spacer()

            // Invisible balance element to center title (matches back button hit target)
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Flame + Count

    var flameSection: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 44) // space for floating header

            ZStack {
                // Layer 1 — diffuse ambient glow (blurred, scaled up copy)
                Image("FlameIcon")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 200)
                    .scaleEffect(viewModel.flameScale * 1.30)
                    .blur(radius: 22)
                    .opacity(0.45 + Double(viewModel.glowRadius - 18) / 20.0 * 0.30)

                // Layer 2 — main crisp flame with pulsing shadow glow
                Image("FlameIcon")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 160, height: 160)
                    .scaleEffect(viewModel.flameScale)
                    .shadow(color: Color(red: 1.0, green: 0.55, blue: 0.05).opacity(0.78), radius: viewModel.glowRadius)
                    .shadow(color: Color.orange.opacity(0.45), radius: viewModel.glowRadius * 1.6)
            }
            .frame(height: 200)

            Text("\(streakManager.currentStreak)")
                .font(.system(size: 88, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(streakText)
                .contentTransition(.numericText())

            Text(AppLocalization.string("streak.detail.weekStreak"))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(streakTextSecondary)
                .tracking(3)
                .textCase(.uppercase)
        }
    }

    // MARK: - Stats Row

    var statsSection: some View {
        AppGlassCard(depth: .elevated, cornerRadius: 18, tint: .clear, contentPadding: 0) {
            HStack(spacing: 0) {
                statColumn(
                    title: AppLocalization.string("streak.detail.streakStarted"),
                    value: formattedDate(streakManager.streakStartDate)
                )

                Rectangle()
                    .fill(streakDivider)
                    .frame(width: 1, height: 40)

                statColumn(
                    title: AppLocalization.string("streak.detail.memberSince"),
                    value: formattedDate(viewModel.actualFirstUseDate ?? streakManager.firstActiveDate)
                )

                Rectangle()
                    .fill(streakDivider)
                    .frame(width: 1, height: 40)

                statColumn(
                    title: AppLocalization.string("streak.detail.best"),
                    value: "\(streakManager.maxStreak)"
                )
            }
            .padding(.vertical, 20)
        }
    }

    func statColumn(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(streakText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(AppTypography.micro)
                .foregroundStyle(streakTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - This Week

    var thisWeekSection: some View {
        AppGlassCard(depth: .base, cornerRadius: 18, tint: .clear, contentPadding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Text(AppLocalization.string("streak.detail.thisWeek"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(streakTextSecondary)
                    .tracking(2)
                    .textCase(.uppercase)

                HStack(spacing: 0) {
                    ForEach(weekDays, id: \.index) { day in
                        weekDayCell(day)
                    }
                }
            }
        }
    }

    func handleStreakDetailAppear() {
        loadHeatmapData()
        syncVacationDurationFromState()
        if shouldAnimate {
            startFlameAnimation()
        }
    }

    func handleVacationStateChange() {
        syncVacationDurationFromState()
    }

    func dismissStreakDetail() {
        dismiss()
    }

    func toggleVacationPicker() {
        Haptics.selection()
        withAnimation(AppMotion.animation(AppMotion.standard, enabled: shouldAnimate)) {
            viewModel.isVacationPickerExpanded.toggle()
        }
    }

    func disableVacationMode() {
        streakManager.disableVacationMode()
    }

    struct WeekDay {
        let index: Int      // 0 = Mon … 6 = Sun (ISO)
        let label: String
        let isToday: Bool
        let isPast: Bool
    }

    var weekDays: [WeekDay] {
        let calendar = Calendar(identifier: .iso8601)
        let now = AppClock.now
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.currentLanguage.locale
        let localizedSymbols = formatter.shortWeekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let isoWeekdayLabels = Array(localizedSymbols.dropFirst()) + [localizedSymbols[0]]
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let isToday = calendar.isDateInToday(date)
            let isPast = date < calendar.startOfDay(for: now) && !isToday
            return WeekDay(index: offset, label: isoWeekdayLabels[offset].uppercased(with: formatter.locale), isToday: isToday, isPast: isPast)
        }
    }

    /// Day-offsets (from ISO week start) that have at least one MetricSample.
    var activeDaysInWeek: Set<Int> {
        let calendar = Calendar(identifier: .iso8601)
        return Set(thisWeekSamples.compactMap { sample in
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: sample.date)?.start else { return nil }
            return calendar.dateComponents([.day], from: weekStart, to: sample.date).day
        })
    }

    func weekDayCell(_ day: WeekDay) -> some View {
        let hasEntry = activeDaysInWeek.contains(day.index)
        let isFuture = !day.isPast && !day.isToday

        return VStack(spacing: 6) {
            Text(day.label)
                .font(.system(size: 10, weight: day.isToday ? .bold : .regular))
                .foregroundStyle(day.isToday ? streakText : streakTextTertiary)

            if hasEntry {
                Image(systemName: "flame.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        ClaudeLightStyle.directionalGradient(
                            colors: day.isToday
                                ? [Color.yellow, Color.orange]
                                : [Color.orange.opacity(0.9), Color.red.opacity(0.7)],
                            colorScheme: colorScheme,
                            lightColor: day.isToday ? Color.appAccent : Color.orange,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                Circle()
                    .strokeBorder(
                        isFuture
                            ? streakDivider
                            : streakTextTertiary,
                        style: StrokeStyle(lineWidth: 1.5, dash: isFuture ? [3, 3] : [])
                    )
                    .frame(width: 22, height: 22)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Next Milestone

    let milestones = [4, 8, 13, 26, 52, 104]

    var nextMilestone: Int {
        milestones.first(where: { $0 > streakManager.currentStreak })
            ?? milestones.last
            ?? max(streakManager.currentStreak, 1)
    }

    var previousMilestone: Int {
        milestones.last(where: { $0 <= streakManager.currentStreak }) ?? 0
    }

    var milestoneProgress: Double {
        let range = Double(nextMilestone - previousMilestone)
        guard range > 0 else { return 1 }
        let done = Double(streakManager.currentStreak - previousMilestone)
        return min(max(done / range, 0), 1)
    }

    var weeksToNextMilestone: Int {
        max(nextMilestone - streakManager.currentStreak, 0)
    }

    var milestoneSection: some View {
        AppGlassCard(depth: .base, cornerRadius: 18, tint: .clear, contentPadding: 16) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    Text(weeksToNextMilestone > 0
                         ? AppLocalization.systemString("Next milestone")
                         : AppLocalization.string("streak.detail.milestone.reached"))
                        .font(AppTypography.eyebrow)
                        .foregroundStyle(streakTextSecondary)
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    MeasureBuddyView(pose: weeksToNextMilestone > 0 ? .streak : .celebration, size: 56)
                }

                HStack(spacing: 14) {
                    milestoneFlameIcon(count: previousMilestone, isActive: true)

                    VStack(spacing: 8) {
                        if weeksToNextMilestone > 0 {
                            Text(AppLocalization.string("streak.detail.nextMilestone.label", weeksToNextMilestone))
                                .font(AppTypography.bodyEmphasis)
                                .foregroundStyle(streakText)

                            Text(AppLocalization.string("streak.detail.nextMilestone.sub"))
                                .font(AppTypography.caption)
                                .foregroundStyle(streakTextSecondary)
                        } else {
                            Text(AppLocalization.string("streak.detail.milestone.reached"))
                                .font(AppTypography.bodyEmphasis)
                                .foregroundStyle(streakText)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(streakMuted)
                                    .frame(height: 6)

                                Capsule()
                                    .fill(
                                        ClaudeLightStyle.directionalGradient(
                                            colors: [Color.yellow, Color.orange],
                                            colorScheme: colorScheme,
                                            lightColor: Color.appAccent,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * milestoneProgress, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }

                    milestoneFlameIcon(count: nextMilestone, isActive: false)
                }

                Rectangle()
                    .fill(streakDivider)
                    .frame(height: 1)

                vacationModeSection
            }
        }
    }

    func milestoneFlameIcon(count: Int, isActive: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.orange.opacity(0.22) : streakMuted)
                    .frame(width: 52, height: 52)

                Image(systemName: "flame.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(
                        isActive
                        ? ClaudeLightStyle.directionalGradient(
                            colors: [.yellow, .orange],
                            colorScheme: colorScheme,
                            lightColor: Color.appAccent,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        : ClaudeLightStyle.directionalGradient(
                            colors: [streakSubtle, streakSubtle.opacity(0.5)],
                            colorScheme: colorScheme,
                            lightColor: streakSubtle,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            Text("\(count)")
                .font(AppTypography.captionEmphasis.monospacedDigit())
                .foregroundStyle(isActive ? streakText : streakSubtle)
        }
    }

    // MARK: - Total Logs

    var totalLogsRow: some View {
        Button {
            showAllLogs = true
        } label: {
            AppGlassCard(depth: .base, cornerRadius: 18, tint: .clear, contentPadding: 16) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.appAccent)

                    Text(AppLocalization.string("streak.detail.totalLogs"))
                        .font(AppTypography.body)
                        .foregroundStyle(streakTextSecondary)

                    Spacer()

                    Text("\(viewModel.totalEntries)")
                        .font(AppTypography.bodyEmphasis.monospacedDigit())
                        .foregroundStyle(streakText)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Motivational Card

    var motivationalCard: some View {
        AppGlassCard(depth: .base, cornerRadius: 18, tint: .orange, contentPadding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(motivationalTitle)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(streakText)

                Text(motivationalBody)
                    .font(AppTypography.body)
                    .foregroundStyle(streakTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var motivationalTier: Int {
        switch streakManager.currentStreak {
        case 0..<4: return 0
        case 4..<8: return 1
        case 8..<13: return 2
        case 13..<26: return 3
        default: return 4
        }
    }

    var motivationalTitle: String {
        AppLocalization.string("streak.detail.motivational.\(motivationalTier).title")
    }

    var motivationalBody: String {
        AppLocalization.string("streak.detail.motivational.\(motivationalTier).body")
    }

    // MARK: - Activity Heatmap data loading

    func loadHeatmapData() {
        let calendar = Calendar(identifier: .iso8601)
        let now = AppClock.now

        // Use the app's first launch date (stored when PremiumStore initializes)
        let firstLaunchTimestamp = UserDefaults.standard.double(forKey: AppSettingsKeys.Premium.firstLaunchDate)
        if firstLaunchTimestamp > 0 {
            viewModel.actualFirstUseDate = Date(timeIntervalSince1970: firstLaunchTimestamp)
        }

        guard let firstDate = streakManager.firstActiveDate else {
            viewModel.totalEntries = (try? modelContext.fetchCount(FetchDescriptor<MetricSample>())) ?? 0
            return
        }

        let descriptor = FetchDescriptor<MetricSample>(
            predicate: #Predicate<MetricSample> { $0.date >= firstDate }
        )
        let samples = (try? modelContext.fetch(descriptor)) ?? []
        viewModel.totalEntries = samples.count

        // Group by start-of-day
        var dayCounts: [Date: Int] = [:]
        for sample in samples {
            let day = calendar.startOfDay(for: sample.date)
            dayCounts[day, default: 0] += 1
        }

        viewModel.allDayCounts = dayCounts

        // Build available years — only years that actually contain samples
        let currentYear = calendar.component(.year, from: now)
        let yearsWithData: Set<Int> = Set(dayCounts.keys.map { calendar.component(.year, from: $0) })
        let firstYear = yearsWithData.min() ?? currentYear
        viewModel.availableYears = Array(stride(from: currentYear, through: firstYear, by: -1))
            .filter { $0 == currentYear || yearsWithData.contains($0) }
        viewModel.selectedYear = currentYear

        if shouldAnimate {
            withAnimation(AppMotion.sectionEnter) {
                viewModel.heatmapRevealed = true
            }
        } else {
            viewModel.heatmapRevealed = true
        }
    }

    // MARK: - Helpers

    func formattedDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    func syncVacationDurationFromState() {
        if let endDate = streakManager.vacationEndDate {
            vacationEndSelection = endDate
        } else {
            vacationEndSelection = Calendar(identifier: .iso8601).date(byAdding: .day, value: 6, to: AppClock.now) ?? AppClock.now
        }
    }

    func applyVacationModeSelection() {
        if streakManager.isVacationModeActive {
            streakManager.updateVacationMode(until: vacationEndSelection)
            viewModel.vacationConfirmationMessage = AppLocalization.string("streak.detail.vacation.confirmation.updated")
        } else {
            streakManager.enableVacationMode(until: vacationEndSelection)
            viewModel.vacationConfirmationMessage = AppLocalization.string("streak.detail.vacation.confirmation.enabled")
        }

        if shouldAnimate {
            withAnimation(AppMotion.standard) {
                viewModel.isVacationPickerExpanded = false
            }
        } else {
            viewModel.isVacationPickerExpanded = false
        }

        Haptics.success()
        if shouldAnimate {
            withAnimation(AppMotion.emphasized) {
                viewModel.vacationCardPulse.toggle()
                viewModel.showVacationConfirmation = true
            }
        } else {
            viewModel.showVacationConfirmation = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1100))
            if shouldAnimate {
                withAnimation(AppMotion.standard) {
                    viewModel.vacationCardPulse = false
                }
            } else {
                viewModel.vacationCardPulse = false
            }

            try? await Task.sleep(for: .milliseconds(1300))
            if shouldAnimate {
                withAnimation(AppMotion.toastOut) {
                    viewModel.showVacationConfirmation = false
                }
            } else {
                viewModel.showVacationConfirmation = false
            }
        }
    }

    func startFlameAnimation() {
        guard !viewModel.animationsStarted else { return }
        viewModel.animationsStarted = true
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            viewModel.flameScale = 1.06
        }
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true).delay(0.5)) {
            viewModel.glowRadius = 38
        }
    }
}
