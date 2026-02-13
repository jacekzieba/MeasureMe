import SwiftUI
import Combine

struct NotificationSettingsView: View {
    @StateObject private var store = ReminderStore()
    @ObservedObject private var notificationManager = NotificationManager.shared
    
    @State private var showAddSheet = false
    @State private var showPermissionAlert = false
    @State private var permissionMessage = ""
    
    @State private var notificationsEnabled: Bool = NotificationManager.shared.notificationsEnabled
    @State private var smartEnabled: Bool = NotificationManager.shared.smartEnabled
    @State private var importNotificationsEnabled: Bool = NotificationManager.shared.importNotificationsEnabled
    @State private var photoRemindersEnabled: Bool = NotificationManager.shared.photoRemindersEnabled
    @State private var goalAchievedEnabled: Bool = NotificationManager.shared.goalAchievedEnabled
    @State private var smartDays: Int = max(NotificationManager.shared.smartDays, 5)
    @State private var smartTime: Date = NotificationManager.shared.smartTime
    
    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(
                topHeight: 380,
                tint: Color.cyan.opacity(0.22)
            )

            List {
                sectionHeader(AppLocalization.string("Reminders"))
                permissionsCard
                if let schedulingError = notificationManager.lastSchedulingError {
                    schedulingErrorCard(message: schedulingError)
                }

                sectionHeader(AppLocalization.string("Scheduled"))
                remindersContent
                sectionFooter(AppLocalization.string("Add one-time or repeatable reminders. You can edit or remove them any time."))

                sectionHeader(AppLocalization.string("Smart Notifications"))
                smartCard
                sectionFooter(AppLocalization.string("Smart reminders only trigger after a period of inactivity. When you log a measurement, the timer resets."))

                sectionHeader(AppLocalization.string("Other"))
                otherCard
                sectionFooter(AppLocalization.string("These notifications are sent when specific events happen."))
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(20)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, -8)
        }
        .navigationTitle(AppLocalization.string("Notifications"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAddSheet) {
            AddReminderSheet { date, repeatRule in
                store.add(date: date, repeatRule: repeatRule)
            }
        }
        .alert(AppLocalization.string("Notifications"), isPresented: $showPermissionAlert) {
            Button(AppLocalization.string("OK"), role: .cancel) { }
        } message: {
            Text(permissionMessage)
        }
    }

    private func schedulingErrorCard(message: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(AppLocalization.string("Notification error"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.red.opacity(0.9))
                Text(message)
                    .font(AppTypography.caption)
                    .foregroundStyle(Color.red.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.sectionTitle)
            .foregroundStyle(.white.opacity(0.78))
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func sectionFooter(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.caption)
            .foregroundStyle(.white.opacity(0.74))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private var remindersContent: some View {
        Group {
            if store.reminders.isEmpty {
                Text(AppLocalization.string("No reminders yet"))
                    .foregroundStyle(.secondary)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(store.reminders) { reminder in
                    GlassCard {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(reminder.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(AppTypography.bodyEmphasis)
                                Text(reminder.repeatRule.title)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onDelete(perform: store.delete)
            }

            Button {
                showAddSheet = true
            } label: {
                Label(AppLocalization.string("Add reminder"), systemImage: "plus.circle.fill")
                    .frame(minHeight: 44, alignment: .leading)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
    
    private var permissionsCard: some View {
        GlassCard {
            Toggle(isOn: $notificationsEnabled) {
                Label(AppLocalization.string("Enable reminders"), systemImage: "bell.badge")
            }
            .frame(minHeight: 44)
            .onChange(of: notificationsEnabled) { _, newValue in
                Task { @MainActor in
                    if newValue {
                        let granted = await NotificationManager.shared.requestAuthorization()
                        if granted {
                            NotificationManager.shared.notificationsEnabled = true
                            store.rescheduleAll()
                            NotificationManager.shared.scheduleSmartIfNeeded()
                            NotificationManager.shared.clearLastSchedulingError()
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
                    }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
    
    private var smartCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $smartEnabled) {
                    Label(AppLocalization.string("Smart reminders"), systemImage: "wand.and.stars")
                }
                .frame(minHeight: 44)
                .onChange(of: smartEnabled) { _, newValue in
                    NotificationManager.shared.smartEnabled = newValue
                    NotificationManager.shared.scheduleSmartIfNeeded()
                }

                Divider()
                    .overlay(Color.white.opacity(0.12))

                HStack(spacing: 12) {
                    Text(AppLocalization.plural("notification.smart.after.days", smartDays))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Stepper("", value: $smartDays, in: 2...30)
                        .labelsHidden()
                }
                .onChange(of: smartDays) { _, newValue in
                    NotificationManager.shared.smartDays = newValue
                    NotificationManager.shared.scheduleSmartIfNeeded()
                }

                Divider()
                    .overlay(Color.white.opacity(0.12))

                HStack(spacing: 12) {
                    Text(AppLocalization.string("Time of day"))
                    Spacer()
                    DatePicker("", selection: $smartTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .onChange(of: smartTime) { _, newValue in
                    NotificationManager.shared.smartTime = newValue
                    NotificationManager.shared.scheduleSmartIfNeeded()
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var otherCard: some View {
        GlassCard {
            Toggle(isOn: $importNotificationsEnabled) {
                Label(AppLocalization.string("Health import notifications"), systemImage: "heart.text.square.fill")
            }
            .frame(minHeight: 44)
            .onChange(of: importNotificationsEnabled) { _, newValue in
                NotificationManager.shared.importNotificationsEnabled = newValue
            }

            Spacer().frame(height: 4)

            Toggle(isOn: $photoRemindersEnabled) {
                Label(AppLocalization.string("Photo reminders"), systemImage: "camera.fill")
            }
            .frame(minHeight: 44)
            .onChange(of: photoRemindersEnabled) { _, newValue in
                NotificationManager.shared.photoRemindersEnabled = newValue
                if newValue {
                    NotificationManager.shared.schedulePhotoReminderIfNeeded()
                } else {
                    NotificationManager.shared.cancelPhotoReminder()
                }
            }

            Spacer().frame(height: 4)

            Toggle(isOn: $goalAchievedEnabled) {
                Label(AppLocalization.string("Goal achieved"), systemImage: "checkmark.seal.fill")
            }
            .frame(minHeight: 44)
            .onChange(of: goalAchievedEnabled) { _, newValue in
                NotificationManager.shared.goalAchievedEnabled = newValue
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

private final class ReminderStore: ObservableObject {
    @Published var reminders: [MeasurementReminder]
    
    init() {
        reminders = NotificationManager.shared.loadReminders().sorted { $0.date < $1.date }
    }
    
    func add(date: Date, repeatRule: ReminderRepeat) {
        let reminder = MeasurementReminder(date: date, repeatRule: repeatRule)
        reminders.append(reminder)
        reminders.sort { $0.date < $1.date }
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
    
    func rescheduleAll() {
        NotificationManager.shared.cancelAllReminders()
        NotificationManager.shared.scheduleAllReminders(reminders)
    }
    
    private func persist() {
        let now = Date()
        reminders = reminders.filter { $0.repeatRule != .once || $0.date > now }
        NotificationManager.shared.saveReminders(reminders)
        NotificationManager.shared.scheduleAllReminders(reminders)
    }
}

private struct AddReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (Date, ReminderRepeat) -> Void
    
    @State private var date: Date = .now.addingTimeInterval(3600)
    @State private var repeatRule: ReminderRepeat = .once
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground(topHeight: 180, tint: Color.cyan.opacity(0.16))
                Form {
                    DatePicker(
                        AppLocalization.string("Reminder time"),
                        selection: $date,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    
                    Picker(AppLocalization.string("Repeat"), selection: $repeatRule) {
                        ForEach(ReminderRepeat.allCases) { rule in
                            Text(rule.title).tag(rule)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(AppLocalization.string("Add Reminder"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) { dismiss() }
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

private struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
    }
}
