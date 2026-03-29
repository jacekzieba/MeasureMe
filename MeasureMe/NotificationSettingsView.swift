import Combine
import SwiftUI
import SwiftData

struct NotificationSettingsView: View {
    @StateObject private var store = ReminderStore()
    @ObservedObject private var notificationManager = NotificationManager.shared
    @EnvironmentObject private var premiumStore: PremiumStore
    @Environment(\.modelContext) private var modelContext

    @State private var showAddSheet = false
    @State private var showPermissionAlert = false
    @State private var permissionMessage = ""
    @State private var showSavedToast = false

    @State private var notificationsEnabled = NotificationManager.shared.notificationsEnabled
    @State private var smartEnabled = NotificationManager.shared.smartEnabled
    @State private var importNotificationsEnabled = NotificationManager.shared.importNotificationsEnabled
    @State private var photoRemindersEnabled = NotificationManager.shared.photoRemindersEnabled
    @State private var goalAchievedEnabled = NotificationManager.shared.goalAchievedEnabled
    @State private var smartDays = max(NotificationManager.shared.smartDays, 5)
    @State private var smartTime = NotificationManager.shared.smartTime
    @State private var perMetricSmartEnabled = NotificationManager.shared.perMetricSmartEnabled
    @State private var aiNotificationsEnabled = NotificationManager.shared.aiNotificationsEnabled
    @State private var aiWeeklyDigestEnabled = NotificationManager.shared.aiWeeklyDigestEnabled
    @State private var aiTrendShiftEnabled = NotificationManager.shared.aiTrendShiftEnabled
    @State private var aiGoalMilestonesEnabled = NotificationManager.shared.aiGoalMilestonesEnabled
    @State private var aiRoundNumbersEnabled = NotificationManager.shared.aiRoundNumbersEnabled
    @State private var aiConsistencyEnabled = NotificationManager.shared.aiConsistencyEnabled
    @State private var aiDigestWeekday = NotificationManager.shared.aiDigestWeekday
    @State private var aiDigestTime = NotificationManager.shared.aiDigestTime

    private let theme = FeatureTheme.settings

    var body: some View {
        SettingsDetailScaffold(title: AppLocalization.string("Notifications"), theme: .settings) {
            remindersSection

            if let schedulingError = notificationManager.lastSchedulingError {
                schedulingErrorSection(message: schedulingError)
            }

            scheduledSection
            smartSection
            aiSection
            otherSection
        }
        .alert(AppLocalization.string("Notifications"), isPresented: $showPermissionAlert) {
            Button(AppLocalization.string("OK"), role: .cancel) { }
        } message: {
            Text(permissionMessage)
        }
        .overlay(alignment: .top) {
            savedToast
        }
        .sheet(isPresented: $showAddSheet) {
            AddReminderSheet { date, repeatRule in
                store.add(date: date, repeatRule: repeatRule)
            }
        }
    }
}

private extension NotificationSettingsView {
    var remindersSection: some View {
        Section {
            SettingsCard(tint: AppColorRoles.surfacePrimary) {
                SettingsToggleRow(isOn: $notificationsEnabled, accent: theme.accent) {
                    Label(AppLocalization.string("Enable reminders"), systemImage: "bell.badge")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textPrimary)
                }
                .onChange(of: notificationsEnabled, enableReminders)
            }
        } header: {
            SettingsSectionEyebrow(title: AppLocalization.string("Reminders"))
        } footer: {
            sectionFooter(AppLocalization.string("Allow notifications"))
        }
        .modifier(NotificationSectionStyle())
    }

    func schedulingErrorSection(message: String) -> some View {
        Section {
            SettingsCard(tint: AppColorRoles.surfacePrimary) {
                SettingsCardHeader(
                    title: AppLocalization.string("Notification error"),
                    systemImage: "exclamationmark.triangle.fill"
                )

                Text(message)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.stateError)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .modifier(NotificationSectionStyle())
    }

    var scheduledSection: some View {
        Section {
            SettingsCard(tint: AppColorRoles.surfacePrimary) {
                SettingsCompactSectionHeader(
                    title: AppLocalization.string("Scheduled"),
                    subtitle: AppLocalization.string("Add one-time or repeatable reminders. You can edit or remove them any time.")
                )

                if store.reminders.isEmpty {
                    SettingsRowDivider()

                    Text(AppLocalization.string("No reminders yet"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(store.reminders) { reminder in
                        SettingsRowDivider()
                        reminderRow(reminder)
                    }
                }

                SettingsRowDivider()

                Button(action: openAddSheet) {
                    HStack(spacing: 12) {
                        GlassPillIcon(systemName: "plus.circle.fill")
                        Text(AppLocalization.string("Add Reminder"))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColorRoles.textPrimary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            SettingsSectionEyebrow(title: AppLocalization.string("Scheduled"))
        }
        .modifier(NotificationSectionStyle())
    }

    var smartSection: some View {
        Section {
            SettingsCard(tint: AppColorRoles.surfacePrimary) {
                SettingsCompactSectionHeader(
                    title: AppLocalization.string("Smart Notifications"),
                    subtitle: AppLocalization.string("Smart reminders only trigger after a period of inactivity. When you log a measurement, the timer resets.")
                )

                SettingsRowDivider()

                SettingsToggleRow(isOn: $smartEnabled, accent: theme.accent) {
                    Label(AppLocalization.string("Smart reminders"), systemImage: "wand.and.stars")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textPrimary)
                }
                .onChange(of: smartEnabled, updateSmartNotifications)

                SettingsRowDivider()

                SettingsValueRow {
                    Text(AppLocalization.plural("notification.smart.after.days", smartDays))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } trailing: {
                    Stepper("", value: $smartDays, in: 2...30)
                        .labelsHidden()
                        .accessibilityLabel(AppLocalization.string("notification.smart.after.days", smartDays))
                }
                .onChange(of: smartDays, updateSmartDays)

                SettingsRowDivider()

                SettingsValueRow {
                    Text(AppLocalization.string("Time of day"))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textPrimary)
                } trailing: {
                    DatePicker("", selection: $smartTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .accessibilityLabel(AppLocalization.string("Time of day"))
                }
                .onChange(of: smartTime, updateSmartTime)

                if smartEnabled {
                    SettingsRowDivider()

                    SettingsToggleRow(isOn: $perMetricSmartEnabled, accent: theme.accent) {
                        Label(
                            AppLocalization.string("notification.smart.permetric.toggle"),
                            systemImage: "list.bullet.clipboard"
                        )
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textPrimary)
                    }
                    .onChange(of: perMetricSmartEnabled, updatePerMetricSmart)

                    Text(AppLocalization.string("notification.smart.permetric.footer"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            SettingsSectionEyebrow(title: AppLocalization.string("Smart Notifications"))
        }
        .modifier(NotificationSectionStyle())
    }

    var otherSection: some View {
        Section {
            SettingsCard(tint: AppColorRoles.surfacePrimary) {
                SettingsCompactSectionHeader(
                    title: AppLocalization.string("Other"),
                    subtitle: AppLocalization.string("These notifications are sent when specific events happen.")
                )

                SettingsRowDivider()

                SettingsToggleRow(isOn: $importNotificationsEnabled, accent: theme.accent) {
                    Label(AppLocalization.string("Health import notifications"), systemImage: "heart.text.square.fill")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textPrimary)
                }
                .onChange(of: importNotificationsEnabled, updateImportNotifications)

                SettingsRowDivider()

                SettingsToggleRow(isOn: $photoRemindersEnabled, accent: theme.accent) {
                    Label(AppLocalization.string("Photo reminders"), systemImage: "camera.fill")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textPrimary)
                }
                .onChange(of: photoRemindersEnabled, updatePhotoReminders)

                SettingsRowDivider()

                SettingsToggleRow(isOn: $goalAchievedEnabled, accent: theme.accent) {
                    Label(AppLocalization.string("Goal achieved"), systemImage: "checkmark.seal.fill")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColorRoles.textPrimary)
                }
                .onChange(of: goalAchievedEnabled, updateGoalNotifications)
            }
        } header: {
            SettingsSectionEyebrow(title: AppLocalization.string("Other"))
        }
        .modifier(NotificationSectionStyle())
    }

    var aiSection: some View {
        Section {
            SettingsCard(tint: FeatureTheme.premium.softTint) {
                SettingsCompactSectionHeader(
                    title: AppLocalization.string("notification.ai.title"),
                    subtitle: AppLocalization.string("notification.ai.subtitle")
                )

                if !premiumStore.isPremium {
                    SettingsRowDivider()
                    Text(AppLocalization.string("Premium Edition required"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                } else if !AppleIntelligenceSupport.isAvailable() || !AINotificationLanguage.isSupported {
                    SettingsRowDivider()
                    Text(AppLocalization.string("notification.ai.unavailable"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                } else {
                    SettingsRowDivider()

                    SettingsToggleRow(isOn: $aiNotificationsEnabled, accent: theme.accent) {
                        Label(AppLocalization.string("notification.ai.master"), systemImage: "sparkles.rectangle.stack")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColorRoles.textPrimary)
                    }
                    .onChange(of: aiNotificationsEnabled, updateAINotifications)

                    if aiNotificationsEnabled {
                        SettingsRowDivider()

                        SettingsToggleRow(isOn: $aiWeeklyDigestEnabled, accent: theme.accent) {
                            Label(AppLocalization.string("notification.ai.weekly"), systemImage: "calendar.badge.clock")
                                .font(AppTypography.body)
                                .foregroundStyle(AppColorRoles.textPrimary)
                        }
                        .onChange(of: aiWeeklyDigestEnabled, updateAIWeeklyDigest)

                        SettingsRowDivider()

                        SettingsToggleRow(isOn: $aiTrendShiftEnabled, accent: theme.accent) {
                            Label(AppLocalization.string("notification.ai.trend"), systemImage: "chart.line.uptrend.xyaxis")
                                .font(AppTypography.body)
                                .foregroundStyle(AppColorRoles.textPrimary)
                        }
                        .onChange(of: aiTrendShiftEnabled, updateAITrendShift)

                        SettingsRowDivider()

                        SettingsToggleRow(isOn: $aiGoalMilestonesEnabled, accent: theme.accent) {
                            Label(AppLocalization.string("notification.ai.goal"), systemImage: "flag.checkered.2.crossed")
                                .font(AppTypography.body)
                                .foregroundStyle(AppColorRoles.textPrimary)
                        }
                        .onChange(of: aiGoalMilestonesEnabled, updateAIGoalMilestones)

                        SettingsRowDivider()

                        SettingsToggleRow(isOn: $aiRoundNumbersEnabled, accent: theme.accent) {
                            Label(AppLocalization.string("notification.ai.round"), systemImage: "number.circle")
                                .font(AppTypography.body)
                                .foregroundStyle(AppColorRoles.textPrimary)
                        }
                        .onChange(of: aiRoundNumbersEnabled, updateAIRoundNumbers)

                        SettingsRowDivider()

                        SettingsToggleRow(isOn: $aiConsistencyEnabled, accent: theme.accent) {
                            Label(AppLocalization.string("notification.ai.consistency"), systemImage: "repeat.circle")
                                .font(AppTypography.body)
                                .foregroundStyle(AppColorRoles.textPrimary)
                        }
                        .onChange(of: aiConsistencyEnabled, updateAIConsistency)

                        SettingsRowDivider()

                        SettingsValueRow {
                            Text(AppLocalization.string("notification.ai.digest.day"))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColorRoles.textPrimary)
                        } trailing: {
                            Picker("", selection: $aiDigestWeekday) {
                                ForEach(1...7, id: \.self) { weekday in
                                    Text(Calendar.current.weekdaySymbols[weekday - 1]).tag(weekday)
                                }
                            }
                            .labelsHidden()
                        }
                        .onChange(of: aiDigestWeekday, updateAIDigestWeekday)

                        SettingsRowDivider()

                        SettingsValueRow {
                            Text(AppLocalization.string("notification.ai.digest.time"))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColorRoles.textPrimary)
                        } trailing: {
                            DatePicker("", selection: $aiDigestTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        .onChange(of: aiDigestTime, updateAIDigestTime)

                        SettingsRowDivider()
                    }

                    Text(AppLocalization.string("notification.ai.disclosure"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            SettingsSectionEyebrow(title: AppLocalization.string("notification.ai.header"))
        }
        .modifier(NotificationSectionStyle())
    }

    @ViewBuilder
    var savedToast: some View {
        if showSavedToast {
            Text(AppLocalization.string("Saved"))
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(AppColorRoles.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.6))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                )
                .padding(.top, 12)
        }
    }

    func reminderRow(_ reminder: MeasurementReminder) -> some View {
        HStack(spacing: 12) {
            GlassPillIcon(systemName: "calendar")

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.date.formatted(date: .abbreviated, time: .shortened))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)

                Text(reminder.repeatRule.title)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
            }

            Spacer()

            Button(role: .destructive) {
                store.delete(id: reminder.id)
            } label: {
                Image(systemName: "trash")
                    .font(AppTypography.iconMedium)
                    .foregroundStyle(AppColorRoles.stateError)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.string("Delete"))
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    func sectionFooter(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.caption)
            .foregroundStyle(AppColorRoles.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
    }

    func acknowledgeSaved() {
        withAnimation(AppMotion.toastIn) {
            showSavedToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(AppMotion.toastOut) {
                showSavedToast = false
            }
        }
    }

    func openAddSheet() {
        showAddSheet = true
    }

    func enableReminders(oldValue: Bool, newValue: Bool) {
        Task { @MainActor in
            if newValue {
                let granted = await NotificationManager.shared.requestAuthorization()
                if granted {
                    NotificationManager.shared.notificationsEnabled = true
                    store.rescheduleAll()
                    NotificationManager.shared.scheduleSmartIfNeeded()
                    NotificationManager.shared.clearLastSchedulingError()
                    acknowledgeSaved()
                } else {
                    notificationsEnabled = false
                    NotificationManager.shared.notificationsEnabled = false
                    permissionMessage = AppLocalization.string("Permission denied. Enable notifications in Settings.")
                    showPermissionAlert = true
                }
            } else {
                NotificationManager.shared.notificationsEnabled = false
                NotificationManager.shared.cancelAllReminders()
                NotificationManager.shared.cancelSmartNotification()
                NotificationManager.shared.cancelPhotoReminder()
                NotificationManager.shared.clearLastSchedulingError()
                acknowledgeSaved()
            }
        }
    }

    func updateSmartNotifications(oldValue: Bool, newValue: Bool) {
        if newValue && !notificationsEnabled {
            Task { @MainActor in
                let granted = await NotificationManager.shared.requestAuthorization()
                if granted {
                    notificationsEnabled = true
                    NotificationManager.shared.notificationsEnabled = true
                    NotificationManager.shared.smartEnabled = true
                    NotificationManager.shared.scheduleSmartIfNeeded()
                    NotificationManager.shared.clearLastSchedulingError()
                    acknowledgeSaved()
                } else {
                    smartEnabled = false
                    NotificationManager.shared.smartEnabled = false
                    permissionMessage = AppLocalization.string("Permission denied. Enable notifications in Settings.")
                    showPermissionAlert = true
                }
            }

            return
        }

        NotificationManager.shared.smartEnabled = newValue
        NotificationManager.shared.scheduleSmartIfNeeded()
        acknowledgeSaved()
    }

    func updateSmartDays(oldValue: Int, newValue: Int) {
        NotificationManager.shared.smartDays = newValue
        NotificationManager.shared.scheduleSmartIfNeeded()
        acknowledgeSaved()
    }

    func updateSmartTime(oldValue: Date, newValue: Date) {
        NotificationManager.shared.smartTime = newValue
        NotificationManager.shared.scheduleSmartIfNeeded()
        acknowledgeSaved()
    }

    func updatePerMetricSmart(oldValue: Bool, newValue: Bool) {
        NotificationManager.shared.perMetricSmartEnabled = newValue
        NotificationManager.shared.scheduleSmartIfNeeded()
        acknowledgeSaved()
    }

    func updateImportNotifications(oldValue: Bool, newValue: Bool) {
        NotificationManager.shared.importNotificationsEnabled = newValue
        acknowledgeSaved()
    }

    func updatePhotoReminders(oldValue: Bool, newValue: Bool) {
        NotificationManager.shared.photoRemindersEnabled = newValue

        if newValue {
            NotificationManager.shared.schedulePhotoReminderIfNeeded()
        } else {
            NotificationManager.shared.cancelPhotoReminder()
        }

        acknowledgeSaved()
    }

    func updateGoalNotifications(oldValue: Bool, newValue: Bool) {
        NotificationManager.shared.goalAchievedEnabled = newValue
        acknowledgeSaved()
    }

    func updateAINotifications(oldValue: Bool, newValue: Bool) {
        if newValue && !notificationsEnabled {
            Task { @MainActor in
                let granted = await NotificationManager.shared.requestAuthorization()
                if granted {
                    notificationsEnabled = true
                    NotificationManager.shared.notificationsEnabled = true
                    NotificationManager.shared.aiNotificationsEnabled = true
                    NotificationManager.shared.scheduleAINotificationsIfNeeded(context: modelContext, trigger: .startup)
                    acknowledgeSaved()
                } else {
                    aiNotificationsEnabled = false
                    NotificationManager.shared.aiNotificationsEnabled = false
                    permissionMessage = AppLocalization.string("Permission denied. Enable notifications in Settings.")
                    showPermissionAlert = true
                }
            }
            return
        }

        NotificationManager.shared.aiNotificationsEnabled = newValue
        if newValue {
            NotificationManager.shared.scheduleAINotificationsIfNeeded(context: modelContext, trigger: .startup)
        } else {
            NotificationManager.shared.cancelAllAINotifications()
        }
        acknowledgeSaved()
    }

    func updateAIWeeklyDigest(oldValue: Bool, newValue: Bool) {
        NotificationManager.shared.aiWeeklyDigestEnabled = newValue
        NotificationManager.shared.scheduleAINotificationsIfNeeded(context: modelContext, trigger: .startup)
        acknowledgeSaved()
    }

    func updateAITrendShift(oldValue: Bool, newValue: Bool) {
        NotificationManager.shared.aiTrendShiftEnabled = newValue
        NotificationManager.shared.scheduleAINotificationsIfNeeded(context: modelContext, trigger: .startup)
        acknowledgeSaved()
    }

    func updateAIGoalMilestones(oldValue: Bool, newValue: Bool) {
        NotificationManager.shared.aiGoalMilestonesEnabled = newValue
        NotificationManager.shared.scheduleAINotificationsIfNeeded(context: modelContext, trigger: .startup)
        acknowledgeSaved()
    }

    func updateAIRoundNumbers(oldValue: Bool, newValue: Bool) {
        NotificationManager.shared.aiRoundNumbersEnabled = newValue
        NotificationManager.shared.scheduleAINotificationsIfNeeded(context: modelContext, trigger: .startup)
        acknowledgeSaved()
    }

    func updateAIConsistency(oldValue: Bool, newValue: Bool) {
        NotificationManager.shared.aiConsistencyEnabled = newValue
        NotificationManager.shared.scheduleAINotificationsIfNeeded(context: modelContext, trigger: .startup)
        acknowledgeSaved()
    }

    func updateAIDigestWeekday(oldValue: Int, newValue: Int) {
        NotificationManager.shared.aiDigestWeekday = newValue
        NotificationManager.shared.scheduleAINotificationsIfNeeded(context: modelContext, trigger: .startup)
        acknowledgeSaved()
    }

    func updateAIDigestTime(oldValue: Date, newValue: Date) {
        NotificationManager.shared.aiDigestTime = newValue
        NotificationManager.shared.scheduleAINotificationsIfNeeded(context: modelContext, trigger: .startup)
        acknowledgeSaved()
    }
}

private final class ReminderStore: ObservableObject {
    @Published var reminders: [MeasurementReminder]

    init() {
        let loaded = NotificationManager.shared.loadReminders()
        let sanitized = Self.sanitize(loaded)
        reminders = sanitized

        if sanitized != loaded {
            NotificationManager.shared.saveReminders(sanitized)
            NotificationManager.shared.scheduleAllReminders(sanitized)
        }
    }

    func add(date: Date, repeatRule: ReminderRepeat) {
        let reminder = MeasurementReminder(date: date, repeatRule: repeatRule)
        reminders = Self.sanitize(reminders + [reminder])
        persist()
    }

    func delete(at offsets: IndexSet) {
        let ids = offsets.map { reminders[$0].id }
        reminders.remove(atOffsets: offsets)

        for id in ids {
            NotificationManager.shared.removeReminder(id: id)
        }

        persist()
    }

    func delete(id: String) {
        reminders.removeAll { $0.id == id }
        NotificationManager.shared.removeReminder(id: id)
        persist()
    }

    func rescheduleAll() {
        NotificationManager.shared.cancelAllReminders()
        NotificationManager.shared.scheduleAllReminders(reminders)
    }

    private func persist() {
        reminders = Self.sanitize(reminders)
        NotificationManager.shared.saveReminders(reminders)
        NotificationManager.shared.scheduleAllReminders(reminders)
    }

    private static func sanitize(_ reminders: [MeasurementReminder]) -> [MeasurementReminder] {
        let now = AppClock.now

        return reminders
            .filter { reminder in
                reminder.repeatRule != .once || reminder.date > now
            }
            .sorted { $0.date < $1.date }
    }
}

private struct AddReminderSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onAdd: (Date, ReminderRepeat) -> Void

    @State private var date: Date = .now.addingTimeInterval(3600)
    @State private var repeatRule: ReminderRepeat = .once

    var body: some View {
        NavigationStack {
            SettingsScrollDetailScaffold(title: AppLocalization.string("Add Reminder"), theme: .settings) {
                SettingsCard(tint: AppColorRoles.surfacePrimary) {
                    SettingsCardHeader(title: AppLocalization.string("Reminder schedule"), systemImage: "calendar")

                    DatePicker(
                        AppLocalization.string("Reminder time"),
                        selection: $date,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                SettingsCard(tint: AppColorRoles.surfacePrimary) {
                    SettingsCardHeader(title: AppLocalization.string("Repeat"), systemImage: "repeat")

                    Picker(AppLocalization.string("Repeat"), selection: $repeatRule) {
                        ForEach(ReminderRepeat.allCases) { rule in
                            Text(rule.title).tag(rule)
                        }
                    }
                    .pickerStyle(.segmented)
                    .glassSegmentedControl(tint: FeatureTheme.settings.accent)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Add")) {
                        onAdd(date, repeatRule)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct NotificationSectionStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .listRowInsets(settingsComponentsRowInsets)
            .listRowBackground(Color.clear)
    }
}
