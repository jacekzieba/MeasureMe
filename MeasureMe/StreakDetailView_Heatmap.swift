import SwiftData
import SwiftUI

// MARK: - Heatmap section

extension StreakDetailView {

    struct MonthCell: Identifiable {
        let id: String
        let count: Int
        let isToday: Bool
        let isVisible: Bool // false for leading/trailing blanks and future/pre-start days
    }

    var activityHeatmapSection: some View {
        AppGlassCard(depth: .base, cornerRadius: 18, tint: .clear, contentPadding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                // Header with title + optional year picker
                HStack {
                    Text(AppLocalization.string("streak.detail.heatmap.title"))
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(streakTextSecondary)
                        .tracking(2)
                        .textCase(.uppercase)

                    Spacer()

                    if viewModel.availableYears.count > 1 {
                        Menu {
                            ForEach(viewModel.availableYears, id: \.self) { year in
                                Button {
                                    viewModel.heatmapRevealed = false
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .milliseconds(40))
                                        viewModel.selectedYear = year
                                        if shouldAnimate {
                                            withAnimation(AppMotion.sectionEnter) {
                                                viewModel.heatmapRevealed = true
                                            }
                                        } else {
                                            viewModel.heatmapRevealed = true
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(String(year))
                                        if year == viewModel.selectedYear {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(String(viewModel.selectedYear))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(streakText)

                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(streakTextSecondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(streakMuted))
                        }
                    }
                }

                // Adaptive grid — only months with potential data
                LazyVGrid(columns: heatmapGridColumns, spacing: 12) {
                    ForEach(Array(visibleMonths.enumerated()), id: \.element) { index, month in
                        miniMonthView(month: month, showDayHeaders: index % 3 == 0)
                    }
                }

                // Legend
                HStack(spacing: 6) {
                    Spacer()
                    Text(AppLocalization.string("streak.detail.heatmap.less"))
                        .font(AppTypography.micro)
                        .foregroundStyle(streakTextTertiary)

                    ForEach(0..<4, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(heatmapColor(for: level))
                            .frame(width: 10, height: 10)
                    }

                    Text(AppLocalization.string("streak.detail.heatmap.more"))
                        .font(AppTypography.micro)
                        .foregroundStyle(streakTextTertiary)
                }
            }
        }
    }

    func miniMonthView(month: Int, showDayHeaders: Bool = false) -> some View {
        let cells = monthCells(month: month)

        return VStack(alignment: .leading, spacing: 3) {
            Text(monthName(month))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(streakTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            let dayCols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

            if showDayHeaders {
                let headers = dayHeaderSymbols()
                LazyVGrid(columns: dayCols, spacing: 2) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(streakSubtle)
                    }
                }
            }

            LazyVGrid(columns: dayCols, spacing: 2) {
                ForEach(cells, id: \.id) { cell in
                    heatmapCellView(cell, monthIndex: month)
                }
            }
        }
    }

    /// Mon–Sun day-of-week symbols in current locale (e.g. P/W/Ś/C/P/S/N for Polish).
    func dayHeaderSymbols() -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? []
        guard symbols.count == 7 else { return [] }
        // Rotate from Sunday-first to ISO Monday-first
        return Array(symbols[1...]) + [symbols[0]]
    }

    func monthCells(month: Int) -> [MonthCell] {
        let calendar = Calendar(identifier: .iso8601)

        // First day of this month
        var comps = DateComponents()
        comps.year = viewModel.selectedYear
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
            dayComps.year = viewModel.selectedYear
            dayComps.month = month
            dayComps.day = day
            guard let date = calendar.date(from: dayComps) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            let isBeforeStart = dayStart < firstActiveStart
            let isToday = calendar.isDateInToday(date)
            let count = viewModel.allDayCounts[dayStart] ?? 0

            cells.append(MonthCell(
                id: "day-\(month)-\(day)",
                count: count,
                isToday: isToday,
                isVisible: !isBeforeStart
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

    func heatmapCellView(_ cell: MonthCell, monthIndex: Int) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(cell.isVisible ? heatmapColor(for: cell.count) : Color.clear)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if cell.isToday && cell.isVisible {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(colorScheme == .dark ? .white.opacity(0.7) : Color.appNavy.opacity(0.5), lineWidth: 1)
                }
            }
            .shadow(
                color: (cell.isVisible && cell.count >= 3)
                    ? Color.appAccent.opacity(0.35) : .clear,
                radius: 2
            )
            .opacity(viewModel.heatmapRevealed ? 1 : 0)
            .scaleEffect(viewModel.heatmapRevealed ? 1 : 0.5)
            .animation(
                shouldAnimate
                    ? .spring(response: 0.3, dampingFraction: 0.8)
                        .delay(Double(monthIndex) * 0.04)
                    : nil,
                value: viewModel.heatmapRevealed
            )
    }

    func heatmapColor(for count: Int) -> Color {
        switch count {
        case 0:     return streakMuted
        case 1:     return Color.orange.opacity(colorScheme == .dark ? 0.3 : 0.35)
        case 2:     return Color.orange.opacity(colorScheme == .dark ? 0.55 : 0.6)
        default:    return Color.appAccent
        }
    }

    /// Months to display for the selected year — from first-active month,
    /// padded to a multiple of 3 so the grid row is always full.
    var visibleMonths: [Int] {
        let calendar = Calendar(identifier: .iso8601)
        let now = AppClock.now
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)

        let firstMonth: Int
        if let firstDate = streakManager.firstActiveDate {
            let firstYear = calendar.component(.year, from: firstDate)
            firstMonth = (firstYear == viewModel.selectedYear)
                ? calendar.component(.month, from: firstDate)
                : 1
        } else {
            firstMonth = 1
        }

        let lastMonth = (viewModel.selectedYear == currentYear) ? currentMonth : 12
        guard firstMonth <= lastMonth else { return [] }

        // Pad to fill the last row of 3 columns (cap at December)
        let count = lastMonth - firstMonth + 1
        let remainder = count % 3
        let padded = (remainder == 0) ? lastMonth : min(lastMonth + (3 - remainder), 12)
        return Array(firstMonth...padded)
    }

    /// Always 3 columns so tiles stay small even with 1–2 months of data.
    var heatmapGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    }

    func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLL"
        var comps = DateComponents()
        comps.year = viewModel.selectedYear
        comps.month = month
        comps.day = 1
        guard let date = Calendar(identifier: .iso8601).date(from: comps) else { return "" }
        return formatter.string(from: date).uppercased()
    }
}
