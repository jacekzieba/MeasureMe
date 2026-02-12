import SwiftUI
import Combine

struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = ReminderStore()
    
    @State private var showAddSheet = false
    @State private var showPermissionAlert = false
    @State private var permissionMessage = ""
    
    @State private var notificationsEnabled: Bool = NotificationManager.shared.notificationsEnabled
    @State private var smartEnabled: Bool = NotificationManager.shared.smartEnabled
    @State private var photoRemindersEnabled: Bool = NotificationManager.shared.photoRemindersEnabled
    @State private var goalAchievedEnabled: Bool = NotificationManager.shared.goalAchievedEnabled
    @State private var smartDays: Int = max(NotificationManager.shared.smartDays, 5)
    @State private var smartTime: Date = NotificationManager.shared.smartTime
    
    var body: some View {
        NavigationStack {
            List {
                permissionsSection
                remindersSection
                otherSection
                smartSection
            }
            .navigationTitle(AppLocalization.string("Notifications"))
            .navigationBarTitleDisplayMode(.inline)
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
    }
    
    private var permissionsSection: some View {
        Section(AppLocalization.string("Reminders")) {
            GlassCard {
                Toggle(isOn: $notificationsEnabled) {
                    Label(AppLocalization.string("Enable reminders"), systemImage: "bell.badge")
                }
                .onChange(of: notificationsEnabled) { _, newValue in
                    Task { @MainActor in
                        if newValue {
                            let granted = await NotificationManager.shared.requestAuthorization()
                            if granted {
                                NotificationManager.shared.notificationsEnabled = true
                                store.rescheduleAll()
                                NotificationManager.shared.scheduleSmartIfNeeded()
                            } else {
                                notificationsEnabled = false
                                NotificationManager.shared.notificationsEnabled = false
                                permissionMessage = "Permission denied. Enable notifications in Settings."
                                showPermissionAlert = true
                            }
                        } else {
                            NotificationManager.shared.notificationsEnabled = false
                            NotificationManager.shared.cancelAllReminders()
                            NotificationManager.shared.cancelSmartNotification()
                        }
                    }
                }
            }
        }
    }
    
    private var remindersSection: some View {
        Section {
            if store.reminders.isEmpty {
                Text(AppLocalization.string("No reminders yet"))
                    .foregroundStyle(.secondary)
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
                }
                .onDelete(perform: store.delete)
            }
            
            Button {
                showAddSheet = true
            } label: {
                Label(AppLocalization.string("Add reminder"), systemImage: "plus.circle.fill")
            }
        } header: {
            Text(AppLocalization.string("Scheduled"))
        } footer: {
            Text(AppLocalization.string("Add one-time or repeatable reminders. You can edit or remove them any time."))
        }
    }
    
    private var smartSection: some View {
        Section {
            GlassCard {
                Toggle(isOn: $smartEnabled) {
                    Label(AppLocalization.string("Smart reminders"), systemImage: "wand.and.stars")
                }
                .onChange(of: smartEnabled) { _, newValue in
                    NotificationManager.shared.smartEnabled = newValue
                    NotificationManager.shared.scheduleSmartIfNeeded()
                }
                Stepper(value: $smartDays, in: 2...30) {
                    Text(AppLocalization.plural("notification.smart.after.days", smartDays))
                }
                .onChange(of: smartDays) { _, newValue in
                    NotificationManager.shared.smartDays = newValue
                    NotificationManager.shared.scheduleSmartIfNeeded()
                }
                
                DatePicker(AppLocalization.string("Time of day"), selection: $smartTime, displayedComponents: .hourAndMinute)
                    .onChange(of: smartTime) { _, newValue in
                        NotificationManager.shared.smartTime = newValue
                        NotificationManager.shared.scheduleSmartIfNeeded()
                    }
            }
        } header: {
            Text(AppLocalization.string("Smart Notifications"))
        } footer: {
            Text(AppLocalization.string("Smart reminders only trigger after a period of inactivity. When you log a measurement, the timer resets."))
        }
    }

    private var otherSection: some View {
        Section {
            GlassCard {
                Toggle(isOn: $photoRemindersEnabled) {
                    Label(AppLocalization.string("Photo reminders"), systemImage: "camera.fill")
                }
                .onChange(of: photoRemindersEnabled) { _, newValue in
                    NotificationManager.shared.photoRemindersEnabled = newValue
                    NotificationManager.shared.scheduleSmartIfNeeded()
                }

                Spacer().frame(height: 4)

                Toggle(isOn: $goalAchievedEnabled) {
                    Label(AppLocalization.string("Goal achieved"), systemImage: "checkmark.seal.fill")
                }
                .onChange(of: goalAchievedEnabled) { _, newValue in
                    NotificationManager.shared.goalAchievedEnabled = newValue
                }
            }
        } header: {
            Text(AppLocalization.string("Other"))
        } footer: {
            Text(AppLocalization.string("These notifications are sent when specific events happen."))
        }
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
            Form {
                DatePicker(
                    "Reminder time",
                    selection: $date,
                    displayedComponents: [.date, .hourAndMinute]
                )
                
                Picker(AppLocalization.string("Repeat"), selection: $repeatRule) {
                    ForEach(ReminderRepeat.allCases) { rule in
                        Text(rule.title).tag(rule)
                    }
                }
            }
            .navigationTitle(AppLocalization.string("Add Reminder"))
            .navigationBarTitleDisplayMode(.inline)
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
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(12)
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
