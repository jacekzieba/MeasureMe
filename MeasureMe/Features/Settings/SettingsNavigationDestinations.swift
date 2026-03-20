import SwiftUI

struct PremiumBenefitsInfoView: View {
    private let theme = FeatureTheme.premium

    var body: some View {
        SettingsDetailScaffold(title: AppLocalization.string("Premium Edition"), theme: .premium) {
            Section {
                SettingsCard(tint: theme.softTint) {
                    SettingsCardHeader(title: AppLocalization.string("settings.app.subscription.active"), systemImage: "checkmark.seal.fill")

                    Text(AppLocalization.string("settings.app.subscription.active.detail"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColorRoles.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    SettingsRowDivider()

                    benefitRow(icon: "sparkles", textKey: "premium.carousel.unlock.item.ai")
                    SettingsRowDivider()
                    benefitRow(icon: "photo.on.rectangle.angled", textKey: "premium.carousel.unlock.item.compare")
                    SettingsRowDivider()
                    benefitRow(icon: "heart.text.square.fill", textKey: "premium.carousel.unlock.item.health")
                    SettingsRowDivider()
                    benefitRow(icon: "doc.text.fill", textKey: "premium.carousel.unlock.item.export")
                    SettingsRowDivider()
                    benefitRow(icon: "flag.fill", textKey: "premium.carousel.unlock.item.support")
                }
            }
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private func benefitRow(icon: String, textKey: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(AppTypography.iconMedium)
                .foregroundStyle(theme.accent)
                .frame(width: 22, alignment: .leading)

            Text(AppLocalization.string(textKey))
                .font(AppTypography.body)
                .foregroundStyle(AppColorRoles.textPrimary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

extension View {
    @ViewBuilder
    func applyNoScrollContentInsetsIfAvailable() -> some View {
        self
    }
}
