import SwiftUI

struct OnboardingReminderSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var repeatRule: ReminderRepeat
    @Binding var weekday: Int
    @Binding var time: Date
    @Binding var onceDate: Date
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppScreenBackground(topHeight: 180, tint: Color.appAccent.opacity(0.16))
                Form {
                    Picker(AppLocalization.systemString("Repeat"), selection: $repeatRule) {
                        ForEach(ReminderRepeat.allCases) { rule in
                            Text(rule.title).tag(rule)
                        }
                    }

                    switch repeatRule {
                    case .once:
                        DatePicker(
                            AppLocalization.systemString("Reminder time"),
                            selection: $onceDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    case .daily:
                        DatePicker(
                            AppLocalization.systemString("Reminder time"),
                            selection: $time,
                            displayedComponents: .hourAndMinute
                        )
                    case .weekly:
                        Picker(AppLocalization.systemString("Reminder day"), selection: $weekday) {
                            ForEach(1...7, id: \.self) { index in
                                Text(weekdayTitle(index)).tag(index)
                            }
                        }

                        DatePicker(
                            AppLocalization.systemString("Reminder time"),
                            selection: $time,
                            displayedComponents: .hourAndMinute
                        )
                    }
                }
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("onboarding.reminder.sheet")
            }
            .navigationTitle(AppLocalization.systemString("Reminder schedule"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.systemString("Cancel")) {
                        dismiss()
                    }
                    .accessibilityIdentifier("onboarding.reminder.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.systemString("Set reminder")) {
                        onConfirm()
                        dismiss()
                    }
                    .accessibilityIdentifier("onboarding.reminder.confirm")
                }
            }
        }
    }

    private func weekdayTitle(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols[safe: weekday - 1] ?? symbols.first ?? "—"
    }
}
