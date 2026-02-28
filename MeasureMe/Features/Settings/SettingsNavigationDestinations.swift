import SwiftUI

struct PremiumBenefitsInfoView: View {
    var body: some View {
        ZStack(alignment: .top) {
            AppScreenBackground(topHeight: 380, tint: Color.appAccent.opacity(0.2))

            List {
                Section {
                    SettingsCard(tint: Color.appAccent.opacity(0.12)) {
                        SettingsCardHeader(title: AppLocalization.string("settings.app.subscription.active"), systemImage: "checkmark.seal.fill")

                        Text(AppLocalization.string("settings.app.subscription.active.detail"))
                            .font(AppTypography.caption)
                            .foregroundStyle(.white.opacity(0.76))
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
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .listSectionSpacing(24)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .padding(.top, 8)
        }
        .navigationTitle(AppLocalization.string("Premium Edition"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func benefitRow(icon: String, textKey: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(AppTypography.iconMedium)
                .foregroundStyle(Color.appAccent)
                .frame(width: 22, alignment: .leading)

            Text(AppLocalization.string(textKey))
                .font(AppTypography.body)
                .foregroundStyle(.white)
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
