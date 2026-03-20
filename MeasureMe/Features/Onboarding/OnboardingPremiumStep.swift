import SwiftUI

/// Krok 3 onboardingu — oferta Premium (bundle benefits + plan picker + CTA).
struct OnboardingPremiumStep: View {
    @EnvironmentObject private var premiumStore: PremiumStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @AppSetting(\.onboarding.onboardingChecklistPremiumExplored) private var onboardingChecklistPremiumExplored: Bool = false

    @State private var selectedProductID: String? = nil

    // MARK: - Computed: products

    private var yearlyProduct: PremiumProduct? {
        premiumStore.products.first { isYearlyPlan($0) }
    }

    private var monthlyProduct: PremiumProduct? {
        premiumStore.products.first { isMonthlyPlan($0) }
    }

    private var onboardingPremiumProducts: [PremiumProduct] {
        premiumStore.products
            .filter { isMonthlyPlan($0) || isYearlyPlan($0) }
            .sorted { $0.price < $1.price }
    }

    private var selectedProduct: PremiumProduct? {
        if let selectedProductID {
            return onboardingPremiumProducts.first { $0.id == selectedProductID }
        }
        return yearlyProduct ?? monthlyProduct
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            onboardingSlideHeader(title: OnboardingView.Step.premium.title, subtitle: OnboardingView.Step.premium.subtitle)

            premiumUnlockBundleTile
            onboardingPlanPicker

            Button {
                onboardingChecklistPremiumExplored = true
                Haptics.light()
                guard let product = selectedProduct else { return }
                Task {
                    premiumStore.setPurchaseContext(reason: .onboarding)
                    await premiumStore.purchase(product)
                }
            } label: {
                Text(AppLocalization.systemString("Start my 14-day free trial"))
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(Color.appAccent)
            .disabled(selectedProduct == nil || premiumStore.isLoading)
            .appHitTarget()
            .accessibilityIdentifier("onboarding.premium.trial")
            .accessibilitySortPriority(3)

            billedAfterTrialText
                .font(AppTypography.micro)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            legalBlock
        }
        .task {
            if premiumStore.products.isEmpty {
                await premiumStore.loadProducts()
            }
            preselectProductIfNeeded()
        }
        .onChange(of: premiumStore.products.map(\.id)) { _, _ in
            preselectProductIfNeeded()
        }
    }

    // MARK: - Bundle tile

    private var premiumUnlockBundleTile: some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 12 : 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.appAccent.opacity(0.26))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "crown.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.appAccent)
                    )

                Text(AppLocalization.string("premium.unlock.bundle.title"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.white.opacity(0.92))
            }

            premiumUnlockBenefitRow(icon: "sparkles",                     tint: Color(hex: "#4ADE80"), textKey: "premium.carousel.unlock.item.ai")
            premiumUnlockBenefitRow(icon: "photo.on.rectangle.angled",    tint: Color(hex: "#60A5FA"), textKey: "premium.carousel.unlock.item.compare")
            premiumUnlockBenefitRow(icon: "heart.text.square.fill",       tint: Color(hex: "#34D399"), textKey: "premium.carousel.unlock.item.health")
            premiumUnlockBenefitRow(icon: "doc.text.fill",                tint: Color(hex: "#FBBF24"), textKey: "premium.carousel.unlock.item.export")
        }
        .padding(dynamicTypeSize.isAccessibilitySize ? AppSpacing.sm : AppSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.09), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        )
    }

    private func premiumUnlockBenefitRow(icon: String, tint: Color, textKey: String) -> some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: dynamicTypeSize.isAccessibilitySize ? 12 : 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(minWidth: 18, alignment: .leading)

            Text(AppLocalization.string(textKey))
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "#FCA311"))
        }
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 4 : 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Plan picker

    private var onboardingPlanPicker: some View {
        VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 14 : 10) {
            if onboardingPremiumProducts.isEmpty {
                LoadingBlock(
                    title: AppLocalization.string("premium.subscription.loading"),
                    accessibilityIdentifier: "onboarding.premium.loading"
                )
            } else {
                ForEach(onboardingPremiumProducts, id: \.id) { product in
                    planRow(product: product)
                }
            }
        }
    }

    private func planRow(product: PremiumProduct) -> some View {
        let isSelected = product.id == selectedProductID
        let secondaryPrice = secondaryPriceLine(for: product)

        return Button {
            selectedProductID = product.id
            Haptics.selection()
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(planTitle(for: product))
                                .font(AppTypography.body)
                                .foregroundStyle(.white.opacity(0.88))
                            Text(planSubtitle(for: product))
                                .font(AppTypography.caption)
                                .foregroundStyle(.white.opacity(0.68))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(primaryPriceLine(for: product))
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.9)

                            if let secondaryPrice {
                                Text(secondaryPrice)
                                    .font(AppTypography.micro)
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(2)
                            }
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(planTitle(for: product))
                                .font(AppTypography.body)
                                .foregroundStyle(.white.opacity(0.88))
                            Text(planSubtitle(for: product))
                                .font(AppTypography.caption)
                                .foregroundStyle(.white.opacity(0.68))
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            Text(primaryPriceLine(for: product))
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.82)

                            if let secondaryPrice {
                                Text(secondaryPrice)
                                    .font(AppTypography.micro)
                                    .foregroundStyle(.white.opacity(0.6))
                                    .minimumScaleFactor(0.9)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(isSelected ? Color.appAccent.opacity(0.16) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .stroke(isSelected ? Color.appAccent : Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Price helpers

    private func planTitle(for product: PremiumProduct) -> String {
        if isMonthlyPlan(product) { return AppLocalization.string("premium.plan.monthly") }
        if isYearlyPlan(product) { return AppLocalization.string("premium.plan.yearly") }
        return product.displayName
    }

    private func planSubtitle(for product: PremiumProduct) -> String {
        if isMonthlyPlan(product) { return AppLocalization.string("premium.plan.billing.monthly") }
        if isYearlyPlan(product) { return AppLocalization.string("premium.plan.billing.yearly") }
        return AppLocalization.string("premium.plan.billing.default")
    }

    private func primaryPriceLine(for product: PremiumProduct) -> String {
        let periodLabel = isYearlyPlan(product)
            ? AppLocalization.string("premium.plan.period.year")
            : AppLocalization.string("premium.plan.period.month")
        return "\(product.displayPrice)/\(periodLabel)"
    }

    private func secondaryPriceLine(for product: PremiumProduct) -> String? {
        guard isYearlyPlan(product) else { return nil }
        let monthlyEquivalent = product.price / Decimal(12)
        let monthlyEquivalentDisplay = formatPrice(monthlyEquivalent, formatter: product.priceFormatter) ?? product.displayPrice
        return AppLocalization.string("premium.plan.equivalent.monthly.dynamic", monthlyEquivalentDisplay)
    }

    // MARK: - Billed text & legal

    private var billedAfterTrialText: Text {
        let product = selectedProduct ?? yearlyProduct ?? monthlyProduct
        guard let product else {
            return Text(AppLocalization.string("premium.cta.billed.after.trial.fallback"))
        }

        let periodLabel = isYearlyPlan(product)
            ? AppLocalization.string("premium.plan.period.year")
            : AppLocalization.string("premium.plan.period.month")

        let amountWithPeriod = "\(product.displayPrice)/\(periodLabel)"
        let prefix = AppLocalization.string("premium.cta.billed.prefix")
        let suffix = AppLocalization.string("premium.cta.billed.suffix")

        var attributed = AttributedString("\(prefix)\(amountWithPeriod)\(suffix)")
        if let emphasizedRange = attributed.range(of: amountWithPeriod) {
            attributed[emphasizedRange].inlinePresentationIntent = .stronglyEmphasized
        }
        return Text(attributed)
    }

    private func isMonthlyPlan(_ product: PremiumProduct) -> Bool {
        product.id == PremiumConstants.monthlyPackageID
            || product.id == PremiumConstants.revenueCatMonthlyPackageID
            || product.productIdentifier == PremiumConstants.monthlyProductID
            || product.productIdentifier == PremiumConstants.legacyMonthlyProductID
    }

    private func isYearlyPlan(_ product: PremiumProduct) -> Bool {
        product.id == PremiumConstants.yearlyPackageID
            || product.id == PremiumConstants.revenueCatYearlyPackageID
            || product.productIdentifier == PremiumConstants.yearlyProductID
            || product.productIdentifier == PremiumConstants.legacyYearlyProductID
    }

    private func formatPrice(_ amount: Decimal, formatter: NumberFormatter?) -> String? {
        guard let formatter else { return nil }
        return formatter.string(from: amount as NSDecimalNumber)
    }

    private func preselectProductIfNeeded() {
        let availableIDs = Set(onboardingPremiumProducts.map(\.id))
        if let selectedProductID, availableIDs.contains(selectedProductID) {
            return
        }

        selectedProductID = yearlyProduct?.id ?? monthlyProduct?.id
    }

    private var legalBlock: some View {
        VStack(spacing: 10) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 10) {
                        Link(AppLocalization.string("Privacy Policy"), destination: LegalLinks.privacyPolicy)
                            .accessibilityIdentifier("onboarding.premium.privacy")
                        Button(AppLocalization.string("Restore purchases")) {
                            Task { await premiumStore.restorePurchases() }
                        }
                        .accessibilityIdentifier("onboarding.premium.restore")
                        Link(AppLocalization.string("Terms of Use"), destination: LegalLinks.termsOfUse)
                            .accessibilityIdentifier("onboarding.premium.terms")
                    }
                } else {
                    HStack(spacing: 18) {
                        Link(AppLocalization.string("Privacy Policy"), destination: LegalLinks.privacyPolicy)
                            .accessibilityIdentifier("onboarding.premium.privacy")
                        Button(AppLocalization.string("Restore purchases")) {
                            Task { await premiumStore.restorePurchases() }
                        }
                        .accessibilityIdentifier("onboarding.premium.restore")
                        Link(AppLocalization.string("Terms of Use"), destination: LegalLinks.termsOfUse)
                            .accessibilityIdentifier("onboarding.premium.terms")
                    }
                }
            }
            .font(AppTypography.captionEmphasis)
            .foregroundStyle(Color.appAccent)

            Text(AppLocalization.string("premium.disclaimer"))
                .font(AppTypography.micro)
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}
