import SwiftUI

struct ExportPDFRangeSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onRangeSelected: (Date?) -> Void

    private let theme = FeatureTheme.settings

    private struct RangeOption: Identifiable {
        let id = UUID()
        let title: String
        let startDate: Date?
    }

    private var options: [RangeOption] {
        let cal = Calendar.current
        let now = AppClock.now
        return [
            RangeOption(
                title: AppLocalization.string("Last month"),
                startDate: cal.date(byAdding: .month, value: -1, to: now)
            ),
            RangeOption(
                title: AppLocalization.string("Last 3 months"),
                startDate: cal.date(byAdding: .month, value: -3, to: now)
            ),
            RangeOption(
                title: AppLocalization.string("Last 6 months"),
                startDate: cal.date(byAdding: .month, value: -6, to: now)
            ),
            RangeOption(
                title: AppLocalization.string("Last year"),
                startDate: cal.date(byAdding: .year, value: -1, to: now)
            ),
            RangeOption(
                title: AppLocalization.string("All time"),
                startDate: nil
            )
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(options) { option in
                        Button {
                            dismiss()
                            onRangeSelected(option.startDate)
                        } label: {
                            HStack {
                                Text(option.title)
                                    .font(AppTypography.body)
                                    .foregroundStyle(AppColorRoles.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(AppColorRoles.textSecondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(AppLocalization.string("Choose date range"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .textCase(nil)
                }
            }
            .navigationTitle(AppLocalization.string("PDF Report"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
