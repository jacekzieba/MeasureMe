import SwiftUI

// MARK: - Vacation mode section

extension StreakDetailView {

    var vacationModeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: streakManager.isVacationModeActive ? "bed.double.fill" : "bed.double")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(streakManager.isVacationModeActive ? Color.orange : streakTextSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(streakMuted))

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalization.string("streak.detail.vacation.title"))
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(streakTextSecondary)
                        .tracking(2)
                        .textCase(.uppercase)

                    Text(vacationStatusText)
                        .font(AppTypography.body)
                        .foregroundStyle(streakText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                toggleVacationPicker()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppLocalization.string("streak.detail.vacation.endDate.label"))
                            .font(AppTypography.caption)
                            .foregroundStyle(streakTextSecondary)

                        Text(formattedDate(vacationEndSelection))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(streakText)
                    }

                    Spacer()

                    Image(systemName: viewModel.isVacationPickerExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(streakTextSecondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(streakMuted)
                )
            }
            .buttonStyle(.plain)

            Group {
                DatePicker(
                    "",
                    selection: $vacationEndSelection,
                    in: Date()...,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(.orange)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(streakMuted)
                )
            }
            .frame(maxHeight: viewModel.isVacationPickerExpanded ? 360 : 0, alignment: .top)
            .opacity(viewModel.isVacationPickerExpanded ? 1 : 0)
            .clipped()
            .allowsHitTesting(viewModel.isVacationPickerExpanded)

            if let endDate = streakManager.vacationEndDate, streakManager.isVacationModeActive {
                Text(AppLocalization.string("streak.detail.vacation.ends", formattedDate(endDate)))
                    .font(AppTypography.caption)
                    .foregroundStyle(streakTextSecondary)
            }

            if viewModel.showVacationConfirmation {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                        .contentTransition(.symbolEffect(.replace))

                    Text(viewModel.vacationConfirmationMessage)
                        .font(AppTypography.caption)
                        .foregroundStyle(streakText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.green.opacity(colorScheme == .dark ? 0.2 : 0.14))
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(spacing: 12) {
                Button(action: applyVacationModeSelection) {
                    Text(
                        AppLocalization.string(
                            streakManager.isVacationModeActive
                                ? "streak.detail.vacation.update"
                                : "streak.detail.vacation.enable"
                        )
                    )
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(Color.black.opacity(0.78))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.orange)
                    )
                }
                .buttonStyle(.plain)

                if streakManager.isVacationModeActive {
                    Button(action: disableVacationMode) {
                        Text(AppLocalization.string("streak.detail.vacation.disable"))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(streakText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(streakMuted)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scaleEffect(viewModel.vacationCardPulse ? 1.015 : 1)
        .shadow(
            color: viewModel.vacationCardPulse ? Color.orange.opacity(colorScheme == .dark ? 0.28 : 0.18) : .clear,
            radius: viewModel.vacationCardPulse ? 18 : 0
        )
        .animation(
            AppMotion.animation(AppMotion.emphasized, enabled: shouldAnimate),
            value: viewModel.vacationCardPulse
        )
        .animation(
            AppMotion.animation(AppMotion.standard, enabled: shouldAnimate),
            value: viewModel.showVacationConfirmation
        )
    }

    var vacationStatusText: String {
        if streakManager.isVacationModeActive {
            return AppLocalization.string(
                "streak.detail.vacation.active",
                AppLocalization.string("streak.detail.vacation.active.date", formattedDate(streakManager.vacationEndDate))
            )
        }
        return AppLocalization.string("streak.detail.vacation.inactive")
    }
}
