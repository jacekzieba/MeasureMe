import Foundation
import SwiftUI

// MARK: - StreakDetailViewModel

@MainActor
final class StreakDetailViewModel: ObservableObject {

    // MARK: - Flame animation state

    @Published var flameScale: CGFloat = 1.0
    @Published var glowRadius: CGFloat = 18
    @Published var animationsStarted = false

    // MARK: - Heatmap state

    @Published var totalEntries: Int = 0
    @Published var allDayCounts: [Date: Int] = [:]
    @Published var selectedYear: Int = 0
    @Published var availableYears: [Int] = []
    @Published var heatmapRevealed = false
    @Published var actualFirstUseDate: Date? = nil

    // MARK: - Vacation state

    @Published var showVacationConfirmation = false
    @Published var vacationConfirmationMessage = ""
    @Published var vacationCardPulse = false
    @Published var isVacationPickerExpanded = false
}
