// BodyModelSetupCards.swift
//
// **BodyModelGenderCard / BodyModelMissingMetricsCard**
// The two cards that stand between a new user and their first silhouette.
//
// **Why not EmptyStateCard:**
// That card combines its children into a single accessibility element, which is
// right for a title-message-button trio and wrong here: the sex picker and the
// list of what is missing have to stay individually reachable.
//
import SwiftUI

/// Lets the user set their sex without leaving the body model screen.
struct BodyModelGenderCard: View {
    @Binding var selectedGender: String

    private let theme = FeatureTheme.photos

    /// Bridges the raw-string binding to an optional so the picker's selection always
    /// matches a `.tag` (`"notSpecified"` and anything unrecognised map to `nil`, which
    /// renders as no segment selected — SwiftUI-defined, not just observed behaviour).
    private var genderSelection: Binding<String?> {
        Binding(
            get: {
                switch selectedGender {
                case Gender.female.rawValue, Gender.male.rawValue:
                    return selectedGender
                default:
                    return nil
                }
            },
            set: { newValue in
                if let newValue {
                    selectedGender = newValue
                }
            }
        )
    }

    var body: some View {
        AppGlassCard(depth: .elevated, cornerRadius: AppRadius.xl, tint: theme.softTint) {
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)

                Text(AppLocalization.string("bodyModel.empty.profile.title"))
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .multilineTextAlignment(.center)

                Text(AppLocalization.string("bodyModel.empty.profile.message"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .multilineTextAlignment(.center)

                Picker(
                    AppLocalization.string("bodyModel.empty.profile.genderLabel"),
                    selection: genderSelection
                ) {
                    Text(Gender.female.displayName).tag(Optional(Gender.female.rawValue))
                    Text(Gender.male.displayName).tag(Optional(Gender.male.rawValue))
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("photos.bodyModel.genderPicker")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.xs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photos.bodyModel.needsProfile")
    }
}

/// Lists what the user still has to log, and opens the sheet that logs it.
struct BodyModelMissingMetricsCard: View {
    let rows: [BodyModelMissingMetrics.Row]
    let onAdd: () -> Void

    private let theme = FeatureTheme.photos

    var body: some View {
        AppGlassCard(depth: .elevated, cornerRadius: AppRadius.xl, tint: theme.softTint) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(AppLocalization.string("bodyModel.empty.metrics.title"))
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColorRoles.textPrimary)

                Text(AppLocalization.string("bodyModel.empty.metrics.listTitle"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textSecondary)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    ForEach(rows) { row in
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: row.systemImage)
                                .font(AppTypography.iconSmall)
                                .foregroundStyle(theme.accent)
                                .frame(width: 24)
                                .accessibilityHidden(true)

                            Text(row.title)
                                .font(AppTypography.body)
                                .foregroundStyle(AppColorRoles.textPrimary)
                        }
                    }
                }

                Button(AppLocalization.string("bodyModel.empty.metrics.action"), action: onAdd)
                    .buttonStyle(AppCTAButtonStyle(size: .compact, cornerRadius: AppRadius.md))
                    .appHitTarget()
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("photos.bodyModel.addMissing")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, AppSpacing.xs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photos.bodyModel.missingMetrics")
    }
}
