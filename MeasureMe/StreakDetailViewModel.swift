import Foundation
import SwiftUI

// MARK: - StreakDetailViewModel

@Observable @MainActor
final class StreakDetailViewModel {

    // MARK: - Flame animation state

    var flameScale: CGFloat = 1.0
    var glowRadius: CGFloat = 18
    var animationsStarted = false

    // MARK: - Heatmap state

    var totalEntries: Int = 0
    var allDayCounts: [Date: Int] = [:]
    var selectedYear: Int = 0
    var availableYears: [Int] = []
    var heatmapRevealed = false
    var actualFirstUseDate: Date? = nil

    // MARK: - Vacation state

    var showVacationConfirmation = false
    var vacationConfirmationMessage = ""
    var vacationCardPulse = false
    var isVacationPickerExpanded = false
}
