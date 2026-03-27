import Foundation

enum SettingsNotificationSummaryState: Equatable {
    case off
    case enabledNoSchedule
    case scheduled(Int)
}

enum SettingsExperienceSummaryState: Equatable {
    case full
    case reduced
    case mixed
}

enum SettingsAppearanceSummaryState: Equatable {
    case system
    case light
    case dark
}

enum SettingsProfileSummaryState: Equatable {
    case empty
    case incomplete
    case named(String)
}

enum SettingsHealthSummaryState: Equatable {
    case off
    case on
    case onLastImport(String)
}

enum SettingsAISummaryState: Equatable {
    case locked
    case unavailable
    case disabled
    case available
}

enum SettingsOverviewSummaryBuilder {
    static func notificationState(
        notificationsEnabled: Bool,
        reminderCount: Int
    ) -> SettingsNotificationSummaryState {
        guard notificationsEnabled else { return .off }
        guard reminderCount > 0 else { return .enabledNoSchedule }
        return .scheduled(reminderCount)
    }

    static func experienceState(
        animationsEnabled: Bool,
        hapticsEnabled: Bool
    ) -> SettingsExperienceSummaryState {
        switch (animationsEnabled, hapticsEnabled) {
        case (true, true):
            return .full
        case (false, false):
            return .reduced
        default:
            return .mixed
        }
    }

    static func appearanceState(appAppearanceRaw: String) -> SettingsAppearanceSummaryState {
        switch AppAppearance(rawValue: appAppearanceRaw) ?? .system {
        case .system:
            return .system
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    static func profileState(
        userName: String,
        userAge: Int,
        manualHeight: Double,
        userGender: String
    ) -> SettingsProfileSummaryState {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return .named(trimmed)
        }

        if userAge > 0 || manualHeight > 0 || userGender != "notSpecified" {
            return .incomplete
        }

        return .empty
    }

    static func trackedMetricCount(metricFlags: [Bool]) -> Int {
        metricFlags.filter { $0 }.count
    }

    static func indicatorsCount(indicatorFlags: [Bool]) -> Int {
        indicatorFlags.filter { $0 }.count
    }

    static func healthState(
        isSyncEnabled: Bool,
        lastImportText: String?
    ) -> SettingsHealthSummaryState {
        guard isSyncEnabled else { return .off }
        if let lastImportText, !lastImportText.isEmpty {
            return .onLastImport(lastImportText)
        }
        return .on
    }

    static func aiState(
        isPremium: Bool,
        isAIAvailable: Bool,
        isAIEnabled: Bool
    ) -> SettingsAISummaryState {
        guard isPremium else { return .locked }
        guard isAIAvailable else { return .unavailable }
        return isAIEnabled ? .available : .disabled
    }
}
