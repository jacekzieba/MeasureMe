import SwiftUI
import SwiftData

// MARK: - History, Empty State, and How-To-Measure Sections

private extension MetricDetailView {

    var emptyStateSection: some View {
        VStack(spacing: 16) {
            kind.iconView(size: 56, tint: measurementsTheme.accent)
                .opacity(0.7)
            VStack(spacing: 6) {
                Text(AppLocalization.string("No data"))
                    .font(AppTypography.displaySection)
                    .foregroundStyle(AppColorRoles.textPrimary)
                Text(AppLocalization.string("Add your first entry to see history and charts."))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(AppLocalization.string("History")) {
                if detailViewModel.samples.count > historyLimit {
                    Button(showAllHistory ? AppLocalization.string("Show Less") : AppLocalization.string("View All")) {
                        showAllHistory.toggle()
                    }
                    .font(AppTypography.sectionAction)
                    .buttonStyle(.plain)
                }
            }

            AppGlassCard(
                depth: .base,
                cornerRadius: 20,
                tint: measurementsTheme.softTint,
                contentPadding: 0
            ) {
                VStack(spacing: 0) {
                    ForEach(Array(visibleHistorySamples.enumerated()), id: \.element.persistentModelID) { index, s in
                        HStack {
                            Text(s.date, style: .date)
                            Spacer()
                            Text(valueString(s.value))
                                .monospacedDigit()
                                .foregroundStyle(AppColorRoles.textSecondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, AppSpacing.smmd)
                        .contentShape(Rectangle())
                        .onTapGesture { edit(sample: s) }
                        .accessibilityLabel({
                            let dateText = s.date.formatted(date: .abbreviated, time: .omitted)
                            return AppLocalization.string("accessibility.entry.detail", dateText, valueString(s.value))
                        }())
                        .accessibilityHint(AppLocalization.string("accessibility.entry.edit"))
                        .swipeActions {
                            Button(role: .destructive) {
                                delete(sample: s)
                            } label: {
                                Label(AppLocalization.string("Delete"), systemImage: "trash")
                            }
                            .tint(.red)
                            Button {
                                edit(sample: s)
                            } label: {
                                Label(AppLocalization.string("Edit"), systemImage: "pencil")
                            }
                            .tint(.blue)
                        }

                        if index < visibleHistorySamples.count - 1 {
                            Divider()
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
    }

    var howToMeasureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(AppLocalization.string("How to measure"))
            Text(measurementInstructions)
                .font(AppTypography.body)
                .foregroundStyle(AppColorRoles.textSecondary)
        }
    }
}
