import SwiftData
import SwiftUI

// MARK: - StreakDetailView

struct StreakDetailView: View {
    @ObservedObject var streakManager: StreakManager

    @Query private var thisWeekSamples: [MetricSample]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var flameScale: CGFloat = 1.0
    @State private var glowRadius: CGFloat = 18
    @State private var totalEntries: Int = 0
    @State private var animationsStarted = false
    @State private var allDayCounts: [Date: Int] = [:]
    @State private var selectedYear: Int = 0
    @State private var availableYears: [Int] = []
    @State private var heatmapRevealed = false

    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldAnimate: Bool {
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
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    flameSection
                    statsSection
                    thisWeekSection
                    if selectedYear > 0 {
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
        .onAppear {
            loadHeatmapData()
            if shouldAnimate {
                startFlameAnimation()
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(AppLocalization.string("streak.detail.title"))
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(.white.opacity(0.7))
                .tracking(2)
                .textCase(.uppercase)

            Spacer()

            // Invisible balance element to center title
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Flame + Count

    private var flameSection: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 44) // space for floating header

            ZStack {
                // Layer 1 — diffuse ambient glow (blurred, scaled up copy)
                Image("FlameIcon")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 200)
                    .scaleEffect(flameScale * 1.30)
                    .blur(radius: 22)
                    .opacity(0.45 + Double(glowRadius - 18) / 20.0 * 0.30)

                // Layer 2 — main crisp flame with pulsing shadow glow
                Image("FlameIcon")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 160, height: 160)
                    .scaleEffect(flameScale)
                    .shadow(color: Color(red: 1.0, green: 0.55, blue: 0.05).opacity(0.78), radius: glowRadius)
                    .shadow(color: Color.orange.opacity(0.45), radius: glowRadius * 1.6)
            }
            .frame(height: 200)

            Text("\(streakManager.currentStreak)")
                .font(.system(size: 88, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            Text(AppLocalization.string("streak.detail.weekStreak"))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(.white.opacity(0.55))
                .tracking(3)
                .textCase(.uppercase)
        }
    }

    // MARK: - Stats Row

    private var statsSection: some View {
        AppGlassCard(depth: .elevated, cornerRadius: 18, tint: .clear, contentPadding: 0) {
            HStack(spacing: 0) {
                statColumn(
                    title: AppLocalization.string("streak.detail.streakStarted"),
                    value: formattedDate(streakManager.streakStartDate)
                )

                Rectangle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 1, height: 40)

                statColumn(
                    title: AppLocalization.string("streak.detail.memberSince"),
                    value: formattedDate(streakManager.firstActiveDate)
                )

                Rectangle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 1, height: 40)

                statColumn(
                    title: AppLocalization.string("streak.detail.best"),
                    value: "\(streakManager.maxStreak)"
                )
            }
            .padding(.vertical, 20)
        }
    }

    private func statColumn(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(AppTypography.micro)
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - This Week

    private var thisWeekSection: some View {
        AppGlassCard(depth: .base, cornerRadius: 18, tint: .clear, contentPadding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Text(AppLocalization.string("streak.detail.thisWeek"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.white.opacity(0.55))
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

    private struct WeekDay {
        let index: Int      // 0 = Mon … 6 = Sun (ISO)
        let label: String
        let isToday: Bool
        let isPast: Bool
    }

    private var weekDays: [WeekDay] {
        let calendar = Calendar(identifier: .iso8601)
        let now = AppClock.now
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        let dayLabels = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let isToday = calendar.isDateInToday(date)
            let isPast = date < calendar.startOfDay(for: now) && !isToday
            return WeekDay(index: offset, label: dayLabels[offset], isToday: isToday, isPast: isPast)
        }
    }

    /// Day-offsets (from ISO week start) that have at least one MetricSample.
    private var activeDaysInWeek: Set<Int> {
        let calendar = Calendar(identifier: .iso8601)
        return Set(thisWeekSamples.compactMap { sample in
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: sample.date)?.start else { return nil }
            return calendar.dateComponents([.day], from: weekStart, to: sample.date).day
        })
    }

    private func weekDayCell(_ day: WeekDay) -> some View {
        let hasEntry = activeDaysInWeek.contains(day.index)
        let isFuture = !day.isPast && !day.isToday

        return VStack(spacing: 6) {
            Text(day.label)
                .font(.system(size: 10, weight: day.isToday ? .bold : .regular))
                .foregroundStyle(day.isToday ? .white : .white.opacity(0.45))

            if hasEntry {
                Image(systemName: "flame.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: day.isToday
                                ? [Color.yellow, Color.orange]
                                : [Color.orange.opacity(0.9), Color.red.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                Circle()
                    .strokeBorder(
                        isFuture
                            ? Color.white.opacity(0.14)
                            : Color.white.opacity(0.26),
                        style: StrokeStyle(lineWidth: 1.5, dash: isFuture ? [3, 3] : [])
                    )
                    .frame(width: 22, height: 22)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Next Milestone

    private let milestones = [4, 8, 13, 26, 52, 104]

    private var nextMilestone: Int {
        milestones.first(where: { $0 > streakManager.currentStreak }) ?? milestones.last!
    }

    private var previousMilestone: Int {
        milestones.last(where: { $0 <= streakManager.currentStreak }) ?? 0
    }

    private var milestoneProgress: Double {
        let range = Double(nextMilestone - previousMilestone)
        guard range > 0 else { return 1 }
        let done = Double(streakManager.currentStreak - previousMilestone)
        return min(max(done / range, 0), 1)
    }

    private var weeksToNextMilestone: Int {
        max(nextMilestone - streakManager.currentStreak, 0)
    }

    private var milestoneSection: some View {
        AppGlassCard(depth: .base, cornerRadius: 18, tint: .clear, contentPadding: 16) {
            HStack(spacing: 14) {
                milestoneFlameIcon(count: previousMilestone, isActive: true)

                VStack(spacing: 8) {
                    if weeksToNextMilestone > 0 {
                        Text(AppLocalization.string("streak.detail.nextMilestone.label", weeksToNextMilestone))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)

                        Text(AppLocalization.string("streak.detail.nextMilestone.sub"))
                            .font(AppTypography.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    } else {
                        Text(AppLocalization.string("streak.detail.milestone.reached"))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.11))
                                .frame(height: 6)

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.yellow, Color.orange],
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
        }
    }

    private func milestoneFlameIcon(count: Int, isActive: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.orange.opacity(0.22) : .white.opacity(0.07))
                    .frame(width: 52, height: 52)

                Image(systemName: "flame.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(
                        isActive
                        ? LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                    )
            }

            Text("\(count)")
                .font(AppTypography.captionEmphasis.monospacedDigit())
                .foregroundStyle(isActive ? .white : .white.opacity(0.35))
        }
    }

    // MARK: - Total Logs

    private var totalLogsRow: some View {
        AppGlassCard(depth: .base, cornerRadius: 18, tint: .clear, contentPadding: 16) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.appAccent)

                Text(AppLocalization.string("streak.detail.totalLogs"))
                    .font(AppTypography.body)
                    .foregroundStyle(.white.opacity(0.72))

                Spacer()

                Text("\(totalEntries)")
                    .font(AppTypography.bodyEmphasis.monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Motivational Card

    private var motivationalCard: some View {
        AppGlassCard(depth: .base, cornerRadius: 18, tint: .orange, contentPadding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(motivationalTitle)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)

                Text(motivationalBody)
                    .font(AppTypography.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var motivationalTier: Int {
        switch streakManager.currentStreak {
        case 0..<4: return 0
        case 4..<8: return 1
        case 8..<13: return 2
        case 13..<26: return 3
        default: return 4
        }
    }

    private var motivationalTitle: String {
        AppLocalization.string("streak.detail.motivational.\(motivationalTier).title")
    }

    private var motivationalBody: String {
        AppLocalization.string("streak.detail.motivational.\(motivationalTier).body")
    }

    // MARK: - Activity Heatmap

    private func loadHeatmapData() {
        let calendar = Calendar(identifier: .iso8601)
        let now = AppClock.now

        guard let firstDate = streakManager.firstActiveDate else {
            totalEntries = (try? modelContext.fetchCount(FetchDescriptor<MetricSample>())) ?? 0
            return
        }

        let descriptor = FetchDescriptor<MetricSample>(
            predicate: #Predicate<MetricSample> { $0.date >= firstDate }
        )
        let samples = (try? modelContext.fetch(descriptor)) ?? []
        totalEntries = samples.count

        // Group by start-of-day
        var dayCounts: [Date: Int] = [:]
        for sample in samples {
            let day = calendar.startOfDay(for: sample.date)
            dayCounts[day, default: 0] += 1
        }

        allDayCounts = dayCounts

        // Build available years
        let firstYear = calendar.component(.year, from: firstDate)
        let currentYear = calendar.component(.year, from: now)
        availableYears = Array(stride(from: currentYear, through: firstYear, by: -1))
        selectedYear = currentYear

        if shouldAnimate {
            withAnimation(AppMotion.sectionEnter) {
                heatmapRevealed = true
            }
        } else {
            heatmapRevealed = true
        }
    }

    private func heatmapColor(for count: Int) -> Color {
        switch count {
        case 0:     return .white.opacity(0.07)
        case 1:     return Color.orange.opacity(0.3)
        case 2:     return Color.orange.opacity(0.55)
        default:    return Color.appAccent
        }
    }

    /// Months to display for the selected year — from first-active month to
    /// current month (current year) or December (past years).
    private var visibleMonths: [Int] {
        let calendar = Calendar(identifier: .iso8601)
        let now = AppClock.now
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)

        let firstMonth: Int
        if let firstDate = streakManager.firstActiveDate {
            let firstYear = calendar.component(.year, from: firstDate)
            firstMonth = (firstYear == selectedYear)
                ? calendar.component(.month, from: firstDate)
                : 1
        } else {
            firstMonth = 1
        }

        let lastMonth = (selectedYear == currentYear) ? currentMonth : 12
        guard firstMonth <= lastMonth else { return [] }
        return Array(firstMonth...lastMonth)
    }

    /// Dynamic column count: 1 for a single month, 2 for 2–4, 3 for 5+.
    private var heatmapGridColumns: [GridItem] {
        let cols: Int
        switch visibleMonths.count {
        case 1:     cols = 1
        case 2...4: cols = 2
        default:    cols = 3
        }
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: cols)
    }

    private var activityHeatmapSection: some View {
        AppGlassCard(depth: .base, cornerRadius: 18, tint: .clear, contentPadding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                // Header with title + optional year picker
                HStack {
                    Text(AppLocalization.string("streak.detail.heatmap.title"))
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(.white.opacity(0.55))
                        .tracking(2)
                        .textCase(.uppercase)

                    Spacer()

                    if availableYears.count > 1 {
                        Menu {
                            ForEach(availableYears, id: \.self) { year in
                                Button {
                                    heatmapRevealed = false
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .milliseconds(40))
                                        selectedYear = year
                                        if shouldAnimate {
                                            withAnimation(AppMotion.sectionEnter) {
                                                heatmapRevealed = true
                                            }
                                        } else {
                                            heatmapRevealed = true
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(String(year))
                                        if year == selectedYear {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(String(selectedYear))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.white)

                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(.white.opacity(0.1)))
                        }
                    }
                }

                // Adaptive grid — only months with potential data
                LazyVGrid(columns: heatmapGridColumns, spacing: 12) {
                    ForEach(visibleMonths, id: \.self) { month in
                        miniMonthView(month: month)
                    }
                }

                // Legend
                HStack(spacing: 6) {
                    Spacer()
                    Text(AppLocalization.string("streak.detail.heatmap.less"))
                        .font(AppTypography.micro)
                        .foregroundStyle(.white.opacity(0.4))

                    ForEach(0..<4, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(heatmapColor(for: level))
                            .frame(width: 10, height: 10)
                    }

                    Text(AppLocalization.string("streak.detail.heatmap.more"))
                        .font(AppTypography.micro)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
    }

    private func miniMonthView(month: Int) -> some View {
        let cells = monthCells(month: month)

        return VStack(alignment: .leading, spacing: 3) {
            Text(monthName(month))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)

            let dayCols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
            LazyVGrid(columns: dayCols, spacing: 2) {
                ForEach(cells, id: \.id) { cell in
                    heatmapCellView(cell, monthIndex: month)
                }
            }
        }
    }

    private struct MonthCell: Identifiable {
        let id: String
        let count: Int
        let isToday: Bool
        let isVisible: Bool // false for leading/trailing blanks and future/pre-start days
    }

    private func monthCells(month: Int) -> [MonthCell] {
        let calendar = Calendar(identifier: .iso8601)
        let now = AppClock.now
        let todayStart = calendar.startOfDay(for: now)

        // First day of this month
        var comps = DateComponents()
        comps.year = selectedYear
        comps.month = month
        comps.day = 1
        guard let firstOfMonth = calendar.date(from: comps) else { return [] }

        let range = calendar.range(of: .day, in: .month, for: firstOfMonth) ?? (1..<31)
        let daysInMonth = range.count

        // ISO 8601: Monday = 1 .. Sunday = 7
        // We want Monday = column 0 .. Sunday = column 6
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        // Convert from Sunday=1..Saturday=7 to Monday=0..Sunday=6
        let leadingBlanks = (firstWeekday + 5) % 7

        // Determine first active date boundary
        let firstActiveStart: Date = {
            if let d = streakManager.firstActiveDate {
                return calendar.startOfDay(for: d)
            }
            return .distantPast
        }()

        var cells: [MonthCell] = []

        // Leading blanks
        for i in 0..<leadingBlanks {
            cells.append(MonthCell(id: "blank-lead-\(month)-\(i)", count: 0, isToday: false, isVisible: false))
        }

        // Actual days
        for day in 1...daysInMonth {
            var dayComps = DateComponents()
            dayComps.year = selectedYear
            dayComps.month = month
            dayComps.day = day
            guard let date = calendar.date(from: dayComps) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            let isBeforeStart = dayStart < firstActiveStart
            let isFuture = dayStart > todayStart
            let isToday = calendar.isDateInToday(date)
            let count = allDayCounts[dayStart] ?? 0

            cells.append(MonthCell(
                id: "day-\(month)-\(day)",
                count: count,
                isToday: isToday,
                isVisible: !isBeforeStart && !isFuture
            ))
        }

        // Trailing blanks to fill last row
        let remainder = cells.count % 7
        if remainder > 0 {
            let trailingBlanks = 7 - remainder
            for i in 0..<trailingBlanks {
                cells.append(MonthCell(id: "blank-trail-\(month)-\(i)", count: 0, isToday: false, isVisible: false))
            }
        }

        return cells
    }

    private func heatmapCellView(_ cell: MonthCell, monthIndex: Int) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(cell.isVisible ? heatmapColor(for: cell.count) : Color.clear)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if cell.isToday && cell.isVisible {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(.white.opacity(0.7), lineWidth: 1)
                }
            }
            .shadow(
                color: (cell.isVisible && cell.count >= 3)
                    ? Color.appAccent.opacity(0.35) : .clear,
                radius: 2
            )
            .opacity(heatmapRevealed ? 1 : 0)
            .scaleEffect(heatmapRevealed ? 1 : 0.5)
            .animation(
                shouldAnimate
                    ? .spring(response: 0.3, dampingFraction: 0.8)
                        .delay(Double(monthIndex) * 0.04)
                    : nil,
                value: heatmapRevealed
            )
    }

    private func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLL"
        var comps = DateComponents()
        comps.year = selectedYear
        comps.month = month
        comps.day = 1
        guard let date = Calendar(identifier: .iso8601).date(from: comps) else { return "" }
        return formatter.string(from: date).uppercased()
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func startFlameAnimation() {
        guard !animationsStarted else { return }
        animationsStarted = true
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            flameScale = 1.06
        }
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true).delay(0.5)) {
            glowRadius = 38
        }
    }
}
