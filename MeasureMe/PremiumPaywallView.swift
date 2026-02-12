import SwiftUI
import StoreKit

struct PremiumPaywallView: View {
    @EnvironmentObject private var premium: PremiumStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProductID: String?

    private var monthly: Product? {
        premium.products.first { $0.id == PremiumConstants.monthlyProductID }
    }

    private var yearly: Product? {
        premium.products.first { $0.id == PremiumConstants.yearlyProductID }
    }

    private var selectedProduct: Product? {
        if let selectedProductID {
            return premium.products.first { $0.id == selectedProductID }
        }
        return yearly ?? monthly
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AppScreenBackground(topHeight: 320)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ScreenTitleHeader(title: AppLocalization.string("Premium Edition"), topPadding: 6, bottomPadding: 6)

                        Text(AppLocalization.string("Go deeper when you need it."))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)

                        Text(AppLocalization.string("Premium adds advanced analysis while core tracking stays free."))
                            .font(AppTypography.caption)
                            .foregroundStyle(.white.opacity(0.7))

                        Text(AppLocalization.string("Built to support your goals and a small business from Poland."))
                            .font(AppTypography.micro)
                            .foregroundStyle(.white.opacity(0.55))

                        benefitsCard
                        planPicker
                        subscribeButton
                        restoreRow

                        Text(AppLocalization.string("premium.disclaimer"))
                            .font(AppTypography.micro)
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.top, 8)

                        HStack(spacing: 16) {
                            Link(AppLocalization.string("Terms"), destination: URL(string: "https://jacekzieba.pl/terms.html")!)
                            Link(AppLocalization.string("Privacy"), destination: URL(string: "https://jacekzieba.pl/privacy.html")!)
                        }
                        .font(AppTypography.microEmphasis)
                        .foregroundStyle(Color.appAccent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Close")) { dismiss() }
                }
            }
            .onAppear {
                if selectedProductID == nil {
                    selectedProductID = yearly?.id ?? monthly?.id
                }
            }
        }
    }

    private var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            benefitRow(AppLocalization.string("premium.benefit.ai"))
            benefitRow(AppLocalization.string("premium.benefit.indicators"))
            benefitRow(AppLocalization.string("premium.benefit.export"))
            benefitRow(AppLocalization.string("premium.benefit.photos"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func benefitRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(hex: "#22C55E"))
            Text(text)
                .font(AppTypography.body)
                .foregroundStyle(.white)
        }
    }

    private var planPicker: some View {
        VStack(spacing: 10) {
            planRow(
                title: AppLocalization.string("premium.plan.monthly"),
                subtitle: AppLocalization.string("premium.plan.trial"),
                price: monthly?.displayPrice ?? "—",
                productID: monthly?.id
            )
            planRow(
                title: AppLocalization.string("premium.plan.yearly"),
                subtitle: AppLocalization.string("premium.plan.savings"),
                price: yearly?.displayPrice ?? "—",
                productID: yearly?.id
            )
        }
    }

    private func planRow(title: String, subtitle: String, price: String, productID: String?) -> some View {
        let isSelected = productID != nil && productID == selectedProductID
        return Button {
            if let productID { selectedProductID = productID }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Text(price)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.appAccent.opacity(0.2) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.appAccent : Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var subscribeButton: some View {
        Button {
            guard let product = selectedProduct else { return }
            Task { await premium.purchase(product) }
        } label: {
            Text(AppLocalization.string("Start Premium"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(AppAccentButtonStyle())
        .disabled(selectedProduct == nil)
    }

    private var restoreRow: some View {
        HStack {
            Button(AppLocalization.string("Restore purchases")) {
                Task { await premium.restorePurchases() }
            }
            Spacer()
            Button(AppLocalization.string("Manage subscription")) {
                premium.openManageSubscriptions()
            }
        }
        .font(AppTypography.captionEmphasis)
        .foregroundStyle(Color.appAccent)
    }
}
