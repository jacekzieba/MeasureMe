import SwiftUI
import UIKit
import RevenueCatUI

struct PremiumPaywallView: View {
    @EnvironmentObject private var premium: PremiumStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var selectedProductID: String?
    @State private var selectedSlide: Int = 0
    @State private var isCTAPulsing: Bool = false
    @State private var isCustomerCenterPresented: Bool = false
    @State private var isRevenueCatPaywallPresented: Bool = false
    @State private var showLifetimeOption: Bool = false
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @AppSetting(\.profile.userName) private var userName: String = ""
    private let premiumTheme = FeatureTheme.premium

    private typealias SlideKind = PremiumSlideKind

    private struct PremiumSlide: Identifiable {
        let id: Int
        let kind: SlideKind
        let icon: String
        let imageAssetName: String?
        let titleKey: String
        let bodyKey: String
        let bulletKeys: [String]
        let tint: Color
        let gradient: [Color]
    }

    private var monthly: PremiumProduct? {
        premium.products.first { isMonthlyPlan($0) }
    }

    private var yearly: PremiumProduct? {
        premium.products.first { isYearlyPlan($0) }
    }

    private var lifetime: PremiumProduct? {
        premium.products.first { isLifetimePlan($0) }
    }

    private var selectedProduct: PremiumProduct? {
        if let selectedProductID {
            return premium.products.first { $0.id == selectedProductID }
        }
        return yearly ?? monthly
    }

    /// Plans shown in the primary plan picker. When the paywall is opened from
    /// `.settings` (`PaywallReason.allowsLifetime == true`) we surface Lifetime
    /// alongside Monthly + Yearly. Contextual paywalls keep subscriptions-only.
    private var availableProducts: [PremiumProduct] {
        premium.products
            .filter { product in
                if isLifetimePlan(product) {
                    return premium.paywallReason.allowsLifetime
                }
                return true
            }
            .sorted { planSortRank($0) < planSortRank($1) }
    }

    /// Order: Yearly first (default selected), then Monthly, then Lifetime.
    private func planSortRank(_ product: PremiumProduct) -> Int {
        if isYearlyPlan(product) { return 0 }
        if isMonthlyPlan(product) { return 1 }
        if isLifetimePlan(product) { return 2 }
        return 3
    }

    /// Unified deep-navy gradient + cyan accent tint shared by every slide.
    /// Keeps the visual language consistent across the carousel — only the
    /// artwork and copy change between slides.
    private static let unifiedSlideGradient: [Color] = [Color(hex: "#11223F"), Color(hex: "#0A122A")]
    private static let unifiedSlideTint: Color = Color.cyan

    /// Six-slide narrative used by the redesigned Premium paywall. `id` is the
    /// `PremiumSlideKind.ordinal` so a `PaywallReason` can target a slide
    /// directly. `imageAssetName` references custom artwork in `Assets.xcassets`;
    /// the carousel falls back to the SF Symbol `icon` if the image is missing.
    private var slides: [PremiumSlide] {
        [
            PremiumSlide(
                id: SlideKind.analyst.ordinal,
                kind: .analyst,
                icon: "sparkles",
                imageAssetName: "premium_slide_analyst",
                titleKey: "premium.carousel.analyst.title",
                bodyKey: "premium.carousel.analyst.body",
                bulletKeys: [
                    "premium.carousel.analyst.bullet.1",
                    "premium.carousel.analyst.bullet.2",
                    "premium.carousel.analyst.bullet.3"
                ],
                tint: Self.unifiedSlideTint,
                gradient: Self.unifiedSlideGradient
            ),
            PremiumSlide(
                id: SlideKind.photos.ordinal,
                kind: .photos,
                icon: "photo.on.rectangle.angled",
                imageAssetName: "premium_slide_photos",
                titleKey: "premium.carousel.photos.title",
                bodyKey: "premium.carousel.photos.body",
                bulletKeys: [
                    "premium.carousel.photos.bullet.1",
                    "premium.carousel.photos.bullet.2",
                    "premium.carousel.photos.bullet.3"
                ],
                tint: Self.unifiedSlideTint,
                gradient: Self.unifiedSlideGradient
            ),
            PremiumSlide(
                id: SlideKind.beyondScale.ordinal,
                kind: .beyondScale,
                icon: "heart.text.square.fill",
                imageAssetName: "premium_slide_beyond_scale",
                titleKey: "premium.carousel.indicators.title",
                bodyKey: "premium.carousel.indicators.body",
                bulletKeys: [
                    "premium.carousel.indicators.bullet.1",
                    "premium.carousel.indicators.bullet.2",
                    "premium.carousel.indicators.bullet.3"
                ],
                tint: Self.unifiedSlideTint,
                gradient: Self.unifiedSlideGradient
            ),
            PremiumSlide(
                id: SlideKind.iCloud.ordinal,
                kind: .iCloud,
                icon: "icloud.and.arrow.up.fill",
                imageAssetName: "premium_slide_icloud",
                titleKey: "premium.carousel.icloud.title",
                bodyKey: "premium.carousel.icloud.body",
                bulletKeys: [
                    "premium.carousel.icloud.bullet.1",
                    "premium.carousel.icloud.bullet.2",
                    "premium.carousel.icloud.bullet.3"
                ],
                tint: Self.unifiedSlideTint,
                gradient: Self.unifiedSlideGradient
            ),
            PremiumSlide(
                id: SlideKind.export.ordinal,
                kind: .export,
                icon: "square.and.arrow.up.on.square.fill",
                imageAssetName: "premium_slide_export",
                titleKey: "premium.carousel.export.title",
                bodyKey: "premium.carousel.export.body",
                bulletKeys: [
                    "premium.carousel.export.bullet.1",
                    "premium.carousel.export.bullet.2",
                    "premium.carousel.export.bullet.3"
                ],
                tint: Self.unifiedSlideTint,
                gradient: Self.unifiedSlideGradient
            ),
            PremiumSlide(
                id: SlideKind.everything.ordinal,
                kind: .everything,
                icon: "star.bubble.fill",
                imageAssetName: "premium_slide_everything",
                titleKey: "premium.carousel.unlock.title",
                bodyKey: "premium.carousel.unlock.body",
                bulletKeys: [
                    "premium.carousel.everything.bullet.1",
                    "premium.carousel.everything.bullet.2",
                    "premium.carousel.everything.bullet.3"
                ],
                tint: Self.unifiedSlideTint,
                gradient: Self.unifiedSlideGradient
            )
        ]
    }

    private var currentSlide: PremiumSlide {
        slides.first { $0.id == selectedSlide } ?? slides[0]
    }

    private func carouselHeight(for viewportHeight: CGFloat) -> CGFloat {
        let isSmallScreen = viewportHeight < 730
        let baseHeight: CGFloat = isSmallScreen ? 430 : 465
        let dynamicTypeBump: CGFloat

        switch dynamicTypeSize {
        case .xLarge:
            dynamicTypeBump = 20
        case .xxLarge:
            dynamicTypeBump = 40
        case .xxxLarge:
            dynamicTypeBump = 60
        case .accessibility1:
            dynamicTypeBump = 100
        case .accessibility2:
            dynamicTypeBump = 130
        case .accessibility3:
            dynamicTypeBump = 160
        case .accessibility4:
            dynamicTypeBump = 190
        case .accessibility5:
            dynamicTypeBump = 220
        default:
            dynamicTypeBump = 0
        }

        return min(baseHeight + dynamicTypeBump, viewportHeight * 0.82)
    }

    private var shouldAnimateCTA: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    private var personalizedFirstName: String? {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(separator: " ").first.map(String.init)
    }

    private var isPolishInterface: Bool {
        switch AppLocalization.currentLanguage {
        case .pl:
            return true
        case .en, .es, .de, .fr, .ptBR:
            return false
        case .system:
            return Locale.preferredLanguages.first?.lowercased().hasPrefix("pl") ?? false
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                paywallBackground

                ScrollView {
                    VStack(spacing: 14) {
                        premiumEditionBadge
                            .padding(.top, 4)

                        carousel(height: carouselHeight(for: proxy.size.height))
                        pageIndicator
                        purchaseDock
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, 16)
                        .padding(.bottom, 28)
                }

                if shouldPresentUITestPostPurchaseSetup && premium.showPostPurchaseSetup {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()

                    VStack(spacing: 12) {
                        Text(AppLocalization.string("postpurchase.title"))
                            .font(AppTypography.displaySection)
                            .multilineTextAlignment(.center)

                        Button(AppLocalization.string("postpurchase.getstarted")) {
                            premium.showPostPurchaseSetup = false
                            premium.dismissPaywall()
                        }
                        .buttonStyle(AppAccentButtonStyle())
                        .accessibilityIdentifier("postpurchase.getstarted")
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("postpurchase.sheet")
                }

                if UITestArgument.isAnyTestMode {
                    VStack(alignment: .leading, spacing: 4) {
                        if premium.canSimulateTrialActivationForUITests {
                            Color.clear
                                .frame(width: 1, height: 1)
                                .accessibilityIdentifier("uitest.debug.premium.simulatedActivation.enabled")
                        }

                        if premium.isPremium {
                            Color.clear
                                .frame(width: 1, height: 1)
                                .accessibilityIdentifier("uitest.debug.premium.active")
                        }

                        if premium.showPostPurchaseSetup {
                            Color.clear
                                .frame(width: 1, height: 1)
                                .accessibilityIdentifier("uitest.debug.postpurchase.flag")
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(false)
                }

                Button {
                    premium.dismissPaywall()
                } label: {
                    Image(systemName: "xmark")
                        .font(AppTypography.iconMedium)
                        .foregroundStyle(AppColorRoles.textPrimary.opacity(0.86))
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(AppColorRoles.surfacePrimary)
                        )
                        .overlay(
                            Circle()
                                .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                        )
                        .contentShape(Circle())
                }
                .padding(.top, 12)
                .padding(.trailing, 16)
                .accessibilityLabel(AppLocalization.string("accessibility.close.premium.paywall"))
                .accessibilityHint(AppLocalization.string("accessibility.close.premium.paywall.hint"))
                .accessibilityIdentifier("premium.paywall.close")
            }
        }
        .onAppear {
            Task { @MainActor in
                premium.clearActionMessage()
                Task {
                    await premium.loadProducts()
                    await premium.syncEntitlements()
                }
                if selectedProductID == nil {
                    selectedProductID = yearly?.id ?? monthly?.id
                }
                // Jump the carousel to the slide most relevant to the trigger.
                selectedSlide = premium.paywallReason.initialSlideKind.ordinal
                Analytics.shared.track(
                    AnalyticsEvents.paywallSlideSeen(
                        slideID: String(selectedSlide),
                        context: premium.paywallReason.analyticsReason
                    )
                )
                if shouldAnimateCTA {
                    isCTAPulsing = true
                }
            }
        }
        .onChange(of: selectedSlide) { _, newSlide in
            Analytics.shared.track(
                AnalyticsEvents.paywallSlideSeen(
                    slideID: String(newSlide),
                    context: premium.paywallReason.analyticsReason
                )
            )
        }
        .onChange(of: selectedProductID) { _, newID in
            guard let newID else { return }
            Analytics.shared.track(
                AnalyticsEvents.paywallPlanSelected(
                    planID: newID,
                    context: premium.paywallReason.analyticsReason
                )
            )
        }
        .onDisappear {
            Analytics.shared.track(
                AnalyticsEvents.paywallClosed(context: premium.paywallReason.analyticsReason)
            )
        }
        .onChange(of: premium.products.map(\.id)) { _, ids in
            guard let selectedProductID else {
                self.selectedProductID = yearly?.id ?? monthly?.id ?? ids.first
                return
            }
            if !ids.contains(selectedProductID) {
                self.selectedProductID = yearly?.id ?? monthly?.id ?? ids.first
            }
        }
        .onChange(of: premium.isPremium) { _, isPremium in
            if isPremium {
                if !shouldPresentUITestPostPurchaseSetup || !premium.showPostPurchaseSetup {
                    premium.dismissPaywall()
                }
            }
        }
        .onChange(of: premium.showPostPurchaseSetup) { _, isPresented in
            guard shouldPresentUITestPostPurchaseSetup else { return }
            guard !isPresented, premium.isPremium else { return }
            premium.dismissPaywall()
        }
        .onChange(of: shouldAnimateCTA) { _, shouldAnimate in
            isCTAPulsing = shouldAnimate
        }
        .presentCustomerCenter(isPresented: $isCustomerCenterPresented)
        .sheet(isPresented: $isRevenueCatPaywallPresented) {
            if let offering = premium.currentOffering {
                PaywallView(offering: offering, displayCloseButton: true)
            } else {
                PaywallView(displayCloseButton: true)
            }
        }
    }

    /// Deeper, richer paywall-only background. Replaces the standard
    /// `AppScreenBackground` with a darker navy stack + accent glow orb,
    /// inspired by the Claude Design redesign while keeping per-slide tinting.
    private var paywallBackground: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let tint = currentSlide.tint

            ZStack(alignment: .top) {
                // Deep base — sits below everything, ignores safe area
                if colorScheme == .dark {
                    Color(hex: "#05090F")
                        .ignoresSafeArea()

                    LinearGradient(
                        colors: [
                            Color(hex: "#0A1628"),
                            Color(hex: "#0E1E38").opacity(0.92),
                            tint.opacity(0.22),
                            Color(hex: "#05090F")
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()

                    // Accent glow orb behind the title — directional, soft
                    RadialGradient(
                        colors: [
                            tint.opacity(0.55),
                            tint.opacity(0.18),
                            .clear
                        ],
                        center: .top,
                        startRadius: 0,
                        endRadius: width * 0.85
                    )
                    .frame(height: 460)
                    .blur(radius: 28)
                    .offset(y: -90)
                    .ignoresSafeArea()

                    // Bottom vignette to sink the dock
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.45)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                } else {
                    // Light mode keeps the standard treatment for accessibility
                    AppScreenBackground(topHeight: 430, tint: tint.opacity(0.24))
                }
            }
        }
        .ignoresSafeArea()
        .animation(AppMotion.animation(AppMotion.standard, enabled: shouldAnimateCTA), value: selectedSlide)
    }

    /// Premium Edition title rendered as an accent pill chip plus a bold
    /// display headline, replacing the plain section-title text.
    private var premiumEditionBadge: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.appAccent)
                Text(AppLocalization.string("Premium Edition").uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Color.appAccent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.appAccent.opacity(colorScheme == .dark ? 0.16 : 0.12))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.appAccent.opacity(0.45), lineWidth: 1)
                    )
            )
            .shadow(color: Color.appAccent.opacity(colorScheme == .dark ? 0.35 : 0.18), radius: 14, y: 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func carousel(height: CGFloat) -> some View {
        TabView(selection: $selectedSlide) {
            ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                VStack(spacing: 8) {
                    headerRow(for: slide)
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 8) {
                            slideHeroImage(for: slide)
                            featureDescriptionCard(for: slide)
                            slideBulletList(for: slide)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            ClaudeLightStyle.directionalGradient(
                                colors: slide.gradient,
                                colorScheme: colorScheme,
                                lightColor: AppColorRoles.surfacePrimary
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                        )
                )
                .tag(slide.id)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(
                    AppLocalization.string(
                        "accessibility.premium.slide.position",
                        "\(index + 1)",
                        "\(slides.count)",
                        AppLocalization.string(slide.titleKey)
                    )
                )
            }
        }
        .frame(height: height)
        .animation(AppMotion.animation(AppMotion.quick, enabled: shouldAnimateCTA), value: selectedSlide)
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    /// Hero artwork for a slide. Tries the named asset first; if it's missing
    /// (older builds before the artwork landed) we drop in a tinted placeholder
    /// so the layout stays stable. Sized so the full slide (header + body +
    /// bullets) fits inside the carousel viewport without internal scrolling.
    @ViewBuilder
    private func slideHeroImage(for slide: PremiumSlide) -> some View {
        if let assetName = slide.imageAssetName, UIImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 175)
                .accessibilityHidden(true)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(slide.tint.opacity(0.18))
                    .frame(height: 140)
                Image(systemName: slide.icon)
                    .font(.system(size: 52, weight: .regular))
                    .foregroundStyle(slide.tint)
            }
            .accessibilityHidden(true)
        }
    }

    /// Three short bullets per slide, rendered compactly so the slide fits
    /// the carousel viewport without internal scrolling.
    private func slideBulletList(for slide: PremiumSlide) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(slide.bulletKeys.enumerated()), id: \.offset) { _, key in
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(slide.tint)
                        .frame(width: 14, alignment: .leading)
                    Text(AppLocalization.string(key))
                        .font(AppTypography.caption)
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(slides) { slide in
                indicatorDot(for: slide.id)
            }
        }
        .animation(AppMotion.animation(AppMotion.quick, enabled: shouldAnimateCTA), value: selectedSlide)
    }

    @ViewBuilder
    private func indicatorDot(for slideID: Int) -> some View {
        let isSelected = slideID == selectedSlide
        let fillColor = isSelected ? AppColorRoles.textPrimary : AppColorRoles.textTertiary
        let dotWidth: CGFloat = isSelected ? 18 : 7
        let position = (slides.firstIndex(where: { $0.id == slideID }) ?? 0) + 1
        let total = slides.count

        Capsule(style: .continuous)
            .fill(fillColor)
            .frame(width: dotWidth, height: 7)
            .accessibilityLabel(
                AppLocalization.string(
                    "accessibility.premium.slide.dot",
                    "\(position)",
                    "\(total)"
                )
            )
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func featureDescriptionCard(for slide: PremiumSlide) -> some View {
        // Promoted to a prominent value-prop card — bigger, brighter, stronger
        // tint backdrop so the user immediately understands what the feature
        // gives them.
        Text(AppLocalization.string(slide.bodyKey))
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [slide.tint.opacity(0.34), slide.tint.opacity(0.14)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(slide.tint.opacity(0.55), lineWidth: 1)
                    )
            )
            .shadow(color: slide.tint.opacity(0.18), radius: 10, y: 4)
    }

    private var slideContentSeparator: some View {
        Rectangle()
            .fill(AppColorRoles.borderSubtle)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 2)
            .padding(.bottom, 2)
    }

    private func headerRow(for slide: PremiumSlide) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(slide.tint.opacity(0.34))
                .frame(width: 36, height: 36)
                .overlay(
                    Circle()
                        .stroke(slide.tint.opacity(0.55), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: slide.icon)
                        .font(AppTypography.iconMedium)
                        .foregroundStyle(AppColorRoles.textPrimary)
                )
                .shadow(color: slide.tint.opacity(0.4), radius: 8, y: 2)

            Text(AppLocalization.string(slide.titleKey))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .tracking(-0.3)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white, Color.white.opacity(0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: slide.tint.opacity(0.55), radius: 12, y: 0)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }


    private func unlockBenefitRow(
        icon: String,
        tint: Color,
        textKey: String,
        accessibilityID: String? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18, alignment: .leading)

            Text(AppLocalization.string(textKey))
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "#FCA311"))
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(accessibilityID ?? textKey)
    }

    private var planPicker: some View {
        VStack(spacing: 12) {
            if availableProducts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    if premium.isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(Color.appAccent)
                            Text(AppLocalization.string("premium.subscription.loading"))
                                .font(AppTypography.caption)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    } else if let error = premium.productsLoadError {
                        Text(AppLocalization.string("premium.subscription.error", error))
                            .font(AppTypography.micro)
                            .foregroundStyle(Color.orange.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                        Button(AppLocalization.string("premium.subscription.retry")) {
                            Task { await premium.loadProducts() }
                        }
                        .buttonStyle(.plain)
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(Color.appAccent)
                        Button("Open RevenueCat Paywall") {
                            isRevenueCatPaywallPresented = true
                        }
                        .buttonStyle(.plain)
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(Color.appAccent)
                    } else {
                        Text(AppLocalization.string("No products returned by RevenueCat."))
                            .font(AppTypography.micro)
                            .foregroundStyle(Color.orange.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                        Button(AppLocalization.string("premium.subscription.retry")) {
                            Task { await premium.loadProducts() }
                        }
                        .buttonStyle(.plain)
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(Color.appAccent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                #if DEBUG
                if availableProducts.isEmpty {
                    let debugMessage = "DEBUG paywall: isLoading=\(premium.isLoading) audit=\(AuditConfig.current.isEnabled) disablePaywall=\(AuditConfig.current.disablePaywallNetwork)"
                    Text(verbatim: debugMessage)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                #endif
            } else {
                ForEach(availableProducts, id: \.id) { product in
                    planRow(product: product)
                }
            }
        }
    }

    private func planRow(product: PremiumProduct) -> some View {
        let isSelected = product.id == selectedProductID
        let subtitle = planSubtitle(for: product)
        let secondaryPrice = secondaryPriceLine(for: product)
        let badge = planBadgeLabel(for: product)

        return Button {
            selectedProductID = product.id
        } label: {
            HStack(spacing: 10) {
                // Selection indicator — not color-only.
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.appAccent : Color.white.opacity(0.45))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(planTitle(for: product))
                            .font(AppTypography.body)
                            .foregroundStyle(.white.opacity(0.88))
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.appAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.appAccent.opacity(0.16), in: Capsule())
                        }
                    }
                    Text(subtitle)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.appAccent.opacity(0.16) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? Color.appAccent : Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func planBadgeLabel(for product: PremiumProduct) -> String? {
        if isYearlyPlan(product) {
            return AppLocalization.string("premium.plan.best.value")
        }
        if isMonthlyPlan(product) {
            return AppLocalization.string("premium.plan.flexible")
        }
        if isLifetimePlan(product) {
            return AppLocalization.string("premium.plan.one.time")
        }
        return nil
    }

    /// Lifetime is included directly in `availableProducts` when the paywall
    /// reason allows it (Settings only). The previous "More options" disclosure
    /// is no longer needed; this view returns nothing.
    @ViewBuilder
    private var lifetimeDisclosure: some View { EmptyView() }

    private var subscribeButtonTitle: String {
        if let product = selectedProduct, isLifetimePlan(product) {
            // No price interpolation — keeps the CTA short and readable.
            return AppLocalization.string("premium.cta.lifetime")
        }
        return AppLocalization.string("premium.cta.trial")
    }

    private var subscribeButton: some View {
        Button {
            if premium.isPremium {
                premium.dismissPaywall()
                return
            }
            let context = premium.paywallReason.analyticsReason
            let planID = selectedProduct?.id ?? "unknown"
            Analytics.shared.track(
                AnalyticsEvents.paywallCTATapped(planID: planID, context: context)
            )
            Task {
                if await premium.activateTrialForUITestsIfNeeded() {
                    return
                }
                guard let product = selectedProduct else { return }
                Analytics.shared.track(
                    AnalyticsEvents.paywallPurchaseStarted(planID: product.id, context: context)
                )
                await premium.purchase(product)
            }
        } label: {
            Text(subscribeButtonTitle)
        }
        .buttonStyle(AppAccentButtonStyle(cornerRadius: 30))
        .disabled(!premium.isPremium && selectedProduct == nil && !premium.canSimulateTrialActivationForUITests)
        .accessibilityIdentifier("premium.paywall.subscribe")
        .scaleEffect(shouldAnimateCTA ? (isCTAPulsing ? 1.0 : 0.975) : 1.0)
        .shadow(
            color: Color.appAccent.opacity(shouldAnimateCTA ? (isCTAPulsing ? 0.48 : 0.24) : 0.18),
            radius: shouldAnimateCTA ? (isCTAPulsing ? 16 : 9) : 7,
            x: 0,
            y: 0
        )
        .animation(
            AppMotion.repeating(AppMotion.pulse, enabled: shouldAnimateCTA),
            value: isCTAPulsing
        )
    }

    private var purchaseDock: some View {
        VStack(spacing: 16) {
            planPicker

            lifetimeDisclosure

            subscribeButton
                .padding(.top, 2)

            // Removed misleading "premium.cta.free.forever" copy — Apple
            // compliance / Premium audit. Plan disclosure below is sufficient.

            billedAfterTrialText
                .font(AppTypography.micro)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            if let actionMessage = premium.actionMessage {
                Text(actionMessage)
                    .font(AppTypography.caption)
                    .foregroundStyle(
                        premium.actionMessageIsError
                        ? Color.orange.opacity(0.95)
                        : AppColorRoles.stateSuccess
                    )
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }

            Text(AppLocalization.string("premium.disclaimer"))
                .font(AppTypography.micro)
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            footerLinks
        }
        .padding(.top, 8)
    }

    private var footerLinks: some View {
        return HStack(spacing: 22) {
            Link(AppLocalization.string("Privacy Policy"), destination: LegalLinks.privacyPolicy)
            Button(AppLocalization.string("Restore purchases")) {
                Task { await premium.restorePurchases() }
            }
            Button(AppLocalization.string("Customer Center")) {
                isCustomerCenterPresented = true
            }
            Link(AppLocalization.string("Terms of Use"), destination: LegalLinks.termsOfUse)
        }
        .font(AppTypography.captionEmphasis)
        .foregroundStyle(Color.appAccent)
        .padding(.top, 4)
    }

    private func planTitle(for product: PremiumProduct) -> String {
        if isMonthlyPlan(product) {
            return AppLocalization.string("premium.plan.monthly")
        }
        if isYearlyPlan(product) {
            return AppLocalization.string("premium.plan.yearly")
        }
        if isLifetimePlan(product) {
            return AppLocalization.string("premium.plan.lifetime")
        }
        return product.displayName
    }

    private func planSubtitle(for product: PremiumProduct) -> String {
        if isMonthlyPlan(product) {
            return AppLocalization.string("premium.plan.billing.monthly")
        }
        if isYearlyPlan(product) {
            return AppLocalization.string("premium.plan.billing.yearly")
        }
        if isLifetimePlan(product) {
            return AppLocalization.string("premium.plan.billing.lifetime")
        }
        return AppLocalization.string("premium.plan.billing.default")
    }

    private func primaryPriceLine(for product: PremiumProduct) -> String {
        if isLifetimePlan(product) {
            return product.displayPrice
        }
        let periodLabel: String
        if isYearlyPlan(product) {
            periodLabel = AppLocalization.string("premium.plan.period.year")
        } else {
            periodLabel = AppLocalization.string("premium.plan.period.month")
        }
        return "\(product.displayPrice)/\(periodLabel)"
    }

    private func secondaryPriceLine(for product: PremiumProduct) -> String? {
        if isYearlyPlan(product) {
            let monthlyEquivalent = product.price / Decimal(12)
            let monthlyEquivalentDisplay = formatPrice(monthlyEquivalent, formatter: product.priceFormatter) ?? product.displayPrice
            return AppLocalization.string("premium.plan.equivalent.monthly.dynamic", monthlyEquivalentDisplay)
        }
        if isLifetimePlan(product) {
            return AppLocalization.string("premium.lifetime.tagline")
        }
        return nil
    }

    private var billedAfterTrialText: Text {
        let product = selectedProduct ?? yearly ?? monthly
        guard let product else {
            return Text(AppLocalization.string("premium.cta.billed.after.trial.fallback"))
        }

        if isLifetimePlan(product) {
            let amount = product.displayPrice
            var attributed = AttributedString(AppLocalization.string("premium.cta.billed.lifetime", amount))
            if let emphasizedRange = attributed.range(of: amount) {
                attributed[emphasizedRange].inlinePresentationIntent = .stronglyEmphasized
            }
            return Text(attributed)
        }

        let periodLabel: String
        if isYearlyPlan(product) {
            periodLabel = AppLocalization.string("premium.plan.period.year")
        } else {
            periodLabel = AppLocalization.string("premium.plan.period.month")
        }

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

    private func isLifetimePlan(_ product: PremiumProduct) -> Bool {
        product.id == PremiumConstants.lifetimePackageID
            || product.id == PremiumConstants.revenueCatLifetimePackageID
            || product.productIdentifier == PremiumConstants.lifetimeProductID
    }

    private func formatPrice(_ amount: Decimal, formatter: NumberFormatter?) -> String? {
        guard let formatter else { return nil }
        return formatter.string(from: amount as NSDecimalNumber)
    }

    private var shouldPresentUITestPostPurchaseSetup: Bool {
        premium.canSimulateTrialActivationForUITests
    }
}

private struct PremiumBeforeAfterSlider: View {
    let beforeImageName: String
    let afterImageName: String
    let beforeLabel: String
    let afterLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @State private var sliderPosition: CGFloat = 0.5
    @State private var isDragging = false
    @State private var hasInteracted = false
    @State private var hasPlayedHintAnimation = false

    private var shouldAnimateHint: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            let clampedSlider = min(max(sliderPosition, 0), 1)

            ZStack {
                Color.black.opacity(0.18)

                premiumPhoto(beforeImageName, width: width, height: height)

                premiumPhoto(afterImageName, width: width, height: height)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: width * clampedSlider)
                    }

                LinearGradient(
                    colors: [.black.opacity(0.20), .clear, .black.opacity(0.36)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack {
                    sliderLabel(beforeLabel)
                        .opacity(clampedSlider > 0.18 ? 1 : 0.35)

                    Spacer()

                    sliderLabel(afterLabel)
                        .opacity(clampedSlider < 0.82 ? 1 : 0.35)
                }
                .padding(14)
                .frame(maxHeight: .infinity, alignment: .bottom)

                sliderHandle(height: height)
                    .position(x: width * clampedSlider, y: height / 2)

                if !hasInteracted {
                    VStack {
                        BeforeAfterSliderInteractionHint(compact: true)
                            .padding(.top, 10)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        hasInteracted = true
                        let newPosition = value.location.x / width
                        guard newPosition.isFinite else { return }
                        sliderPosition = min(max(newPosition, 0), 1)
                    }
                    .onEnded { _ in
                        isDragging = false
                        if abs(sliderPosition - 0.5) < 0.05 {
                            withAnimation(AppMotion.standard) {
                                sliderPosition = 0.5
                            }
                        }
                    }
            )
            .task(id: width) {
                await playHintAnimation()
            }
        }
    }

    @MainActor
    private func playHintAnimation() async {
        guard shouldAnimateHint, !hasPlayedHintAnimation, !hasInteracted else { return }
        hasPlayedHintAnimation = true

        try? await Task.sleep(nanoseconds: 450_000_000)
        guard !Task.isCancelled, !hasInteracted else { return }
        withAnimation(.easeInOut(duration: 0.34)) {
            sliderPosition = 0.42
        }

        try? await Task.sleep(nanoseconds: 380_000_000)
        guard !Task.isCancelled, !hasInteracted else { return }
        withAnimation(.easeInOut(duration: 0.42)) {
            sliderPosition = 0.58
        }

        try? await Task.sleep(nanoseconds: 440_000_000)
        guard !Task.isCancelled, !hasInteracted else { return }
        withAnimation(.easeInOut(duration: 0.34)) {
            sliderPosition = 0.5
        }
    }

    private func premiumPhoto(_ imageName: String, width: CGFloat, height: CGFloat) -> some View {
        Image(imageName)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height, alignment: .center)
            .clipped()
    }

    private func sliderLabel(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.captionEmphasis)
            .foregroundStyle(Color.appWhite)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.34), in: Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
    }

    private func sliderHandle(height: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.appWhite.opacity(0.94))
                .frame(width: isDragging ? 4 : 3, height: height)
                .shadow(color: .black.opacity(0.24), radius: 8)

            Circle()
                .fill(Color.appWhite)
                .frame(width: isDragging ? 50 : 44, height: isDragging ? 50 : 44)
                .shadow(color: .black.opacity(0.32), radius: 10, y: 4)
                .overlay {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColorRoles.textTertiary)
                }
        }
    }
}
