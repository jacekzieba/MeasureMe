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
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @AppSetting(\.profile.userName) private var userName: String = ""
    private let premiumTheme = FeatureTheme.premium

    private enum SlideKind {
        case analyst
        case photos
        case indicators
        case unlock
    }

    private struct PremiumSlide: Identifiable {
        let id: Int
        let kind: SlideKind
        let icon: String
        let titleKey: String
        let bodyKey: String
        let tint: Color
        let gradient: [Color]
    }

    private var monthly: PremiumProduct? {
        premium.products.first { isMonthlyPlan($0) }
    }

    private var yearly: PremiumProduct? {
        premium.products.first { isYearlyPlan($0) }
    }

    private var selectedProduct: PremiumProduct? {
        if let selectedProductID {
            return premium.products.first { $0.id == selectedProductID }
        }
        return yearly ?? monthly
    }

    private var availableProducts: [PremiumProduct] {
        premium.products.sorted { $0.price < $1.price }
    }

    private var slides: [PremiumSlide] {
        [
            PremiumSlide(
                id: 0,
                kind: .analyst,
                icon: "sparkles",
                titleKey: "premium.carousel.analyst.title",
                bodyKey: "premium.carousel.analyst.body",
                tint: Color.cyan,
                gradient: [Color(hex: "#11223F"), Color(hex: "#0A122A")]
            ),
            PremiumSlide(
                id: 1,
                kind: .photos,
                icon: "photo.on.rectangle.angled",
                titleKey: "premium.carousel.photos.title",
                bodyKey: "premium.carousel.photos.body",
                tint: Color(hex: "#7C8CFF"),
                gradient: [Color(hex: "#1A2146"), Color(hex: "#0E1530")]
            ),
            PremiumSlide(
                id: 2,
                kind: .indicators,
                icon: "heart.text.square.fill",
                titleKey: "premium.carousel.indicators.title",
                bodyKey: "premium.carousel.indicators.body",
                tint: Color.green,
                gradient: [Color(hex: "#132C2B"), Color(hex: "#0A1719")]
            ),
            PremiumSlide(
                id: 3,
                kind: .unlock,
                icon: "star.bubble.fill",
                titleKey: "premium.carousel.unlock.title",
                bodyKey: "premium.carousel.unlock.body",
                tint: Color.appAccent,
                gradient: [Color(hex: "#3A2712"), Color(hex: "#1A1410")]
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
                AppScreenBackground(topHeight: 430, tint: currentSlide.tint.opacity(0.24))

                ScrollView {
                    VStack(spacing: 14) {
                        Text(AppLocalization.string("Premium Edition"))
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(AppColorRoles.textPrimary)
                            .multilineTextAlignment(.center)

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
                if shouldAnimateCTA {
                    isCTAPulsing = true
                }
            }
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

    private func carousel(height: CGFloat) -> some View {
        TabView(selection: $selectedSlide) {
            ForEach(slides) { slide in
                VStack(spacing: 10) {
                    headerRow(for: slide)
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 10) {
                            if slide.kind != .unlock {
                                featureDescriptionCard(for: slide)
                            }
                            slideContentSeparator
                            supplementaryContent(for: slide)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
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
            }
        }
        .frame(height: height)
        .animation(AppMotion.animation(AppMotion.quick, enabled: shouldAnimateCTA), value: selectedSlide)
        .tabViewStyle(.page(indexDisplayMode: .never))
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

        Capsule(style: .continuous)
            .fill(fillColor)
            .frame(width: dotWidth, height: 7)
    }

    private func featureDescriptionCard(for slide: PremiumSlide) -> some View {
        Text(AppLocalization.string(slide.bodyKey))
            .font(AppTypography.bodyEmphasis)
            .foregroundStyle(AppColorRoles.textPrimary.opacity(0.95))
            .multilineTextAlignment(.leading)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        ClaudeLightStyle.directionalGradient(
                            colors: [slide.tint.opacity(0.22), AppColorRoles.surfaceSecondary],
                            colorScheme: colorScheme,
                            lightColor: slide.tint.opacity(0.08)
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                    )
            )
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
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(slide.tint.opacity(0.34))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: slide.icon)
                        .font(AppTypography.iconSmall)
                        .foregroundStyle(AppColorRoles.textPrimary)
                )

            Text(AppLocalization.string(slide.titleKey))
                .font(AppTypography.headlineEmphasis)
                .foregroundStyle(AppColorRoles.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func supplementaryContent(for slide: PremiumSlide) -> some View {
        switch slide.kind {
        case .analyst:
            aiInsightPreview
        case .photos:
            photoComparisonPreview
        case .indicators:
            indicatorsPreview
        case .unlock:
            unlockListPreview
        }
    }

    private var aiInsightPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(AppColorRoles.surfacePrimary)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(AppTypography.iconSmall)
                            .foregroundStyle(Color.appAccent)
                    )

                Text(AppLocalization.string("premium.carousel.insight.header"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary.opacity(0.92))
            }

            Text(aiInsightAttributedText)
            .font(AppTypography.captionEmphasis)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(AppTypography.iconSmall)
                    .foregroundStyle(Color.appAccent.opacity(0.82))

                Text(AppLocalization.string("premium.carousel.insight.tip"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(Color.appAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(premiumTheme.pillFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(premiumTheme.border, lineWidth: 1)
                    )
            )

            if isPolishInterface {
                Text(AppLocalization.string("premium.carousel.insight.language.note"))
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    ClaudeLightStyle.directionalGradient(
                        colors: [Color(hex: "#1E2850").opacity(0.85), Color.black.opacity(0.45)],
                        colorScheme: colorScheme,
                        lightColor: AppColorRoles.surfaceSecondary
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                )
        )
    }

    private var aiInsightAttributedText: AttributedString {
        var text = AttributedString()

        if let name = personalizedFirstName {
            var namePart = AttributedString("\(name), ")
            namePart.foregroundColor = Color.appAccent
            text += namePart
        }

        var part1 = AttributedString(AppLocalization.string("premium.carousel.insight.body.part1"))
        part1.foregroundColor = Color.white.opacity(0.92)
        text += part1

        var valuePart = AttributedString(" -0.3 kg/week ")
        valuePart.foregroundColor = AppColorRoles.stateSuccess
        text += valuePart

        var part2 = AttributedString(AppLocalization.string("premium.carousel.insight.body.part2"))
        part2.foregroundColor = Color.white.opacity(0.92)
        text += part2

        text += AttributedString("\n\n")

        var part3 = AttributedString(AppLocalization.string("premium.carousel.insight.body.part3"))
        part3.foregroundColor = Color.white.opacity(0.92)
        text += part3

        var bicepsValue = AttributedString(" +0.8 cm ")
        bicepsValue.foregroundColor = Color(hex: "#60A5FA")
        text += bicepsValue

        var part4 = AttributedString(AppLocalization.string("premium.carousel.insight.body.part4"))
        part4.foregroundColor = Color.white.opacity(0.92)
        text += part4

        return text
    }

    @ViewBuilder
    private var photoComparisonPreview: some View {
        comparisonToolMockup
    }

    private var comparisonToolMockup: some View {
        let pastDate = Calendar.current.date(byAdding: .day, value: -30, to: AppClock.now) ?? AppClock.now
        let pastLabel = pastDate.formatted(date: .abbreviated, time: .omitted)
        let presentLabel = AppClock.now.formatted(date: .abbreviated, time: .omitted)

        return VStack(spacing: 10) {
            PremiumBeforeAfterSlider(
                beforeImageName: "onboarding-after-recomp",
                afterImageName: "onboarding-before-recomp",
                beforeLabel: AppLocalization.string("premium.carousel.compare.before"),
                afterLabel: AppLocalization.string("premium.carousel.compare.after")
            )
            .frame(height: 210)

            HStack(spacing: 6) {
                Image(systemName: "arrow.left.and.right.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(pastLabel)
                Text("↔")
                Text(presentLabel)
            }
            .font(AppTypography.microEmphasis)
            .foregroundStyle(Color(hex: "#F5A623"))
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var indicatorsPreview: some View {
        VStack(spacing: 8) {
            indicatorRow(
                icon: "waveform.path.ecg",
                title: AppLocalization.string("premium.carousel.indicator.absi"),
                value: "0.079",
                status: AppLocalization.string("premium.carousel.indicator.status.attention"),
                tint: Color(hex: "#F59E0B")
            )

            indicatorRow(
                icon: "arrow.up.and.down.and.arrow.left.and.right",
                title: AppLocalization.string("premium.carousel.indicator.whtr"),
                value: "0.48",
                status: AppLocalization.string("premium.carousel.indicator.status.good"),
                tint: AppColorRoles.stateSuccess
            )

            Text(AppLocalization.string("premium.carousel.indicators.more"))
                .font(AppTypography.microEmphasis)
                .foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 38)
                .padding(.top, 2)

            indicatorDetailSpotlightCard
        }
    }

    private var indicatorDetailSpotlightCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(AppLocalization.string("Waist-to-Height Ratio"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.white.opacity(0.92))
                Spacer(minLength: 8)
                Text(AppLocalization.string("WHtR"))
                    .font(AppTypography.microEmphasis)
                    .foregroundStyle(Color.appAccent)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("0.48")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Spacer(minLength: 8)
                Text(AppLocalization.string("premium.carousel.indicator.status.good"))
                    .font(AppTypography.microEmphasis)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppColorRoles.stateSuccess, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Text(AppLocalization.string("premium.carousel.indicator.preview.copy"))
                .font(AppTypography.caption)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
                Text(AppLocalization.string("premium.carousel.indicator.preview.about"))
                    .font(AppTypography.micro)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private func indicatorRow(icon: String, title: String, value: String, status: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint.opacity(0.24))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(status)
                    .font(AppTypography.micro)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Text(value)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }

    private var unlockListPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
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
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.92) : AppColorRoles.textPrimary)
                }

                Text(AppLocalization.string("premium.carousel.unlock.body"))
                    .font(AppTypography.caption)
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.82) : AppColorRoles.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                unlockBenefitRow(icon: "sparkles", tint: Color(hex: "#4ADE80"), textKey: "premium.carousel.unlock.item.ai")
                unlockBenefitRow(icon: "photo.on.rectangle.angled", tint: Color(hex: "#60A5FA"), textKey: "premium.carousel.unlock.item.compare")
                unlockBenefitRow(icon: "heart.text.square.fill", tint: Color(hex: "#34D399"), textKey: "premium.carousel.unlock.item.health")
                unlockBenefitRow(icon: "chart.line.uptrend.xyaxis", tint: Color(hex: "#F472B6"), textKey: "premium.carousel.unlock.item.prediction")
                unlockBenefitRow(icon: "doc.text.fill", tint: Color(hex: "#FBBF24"), textKey: "premium.carousel.unlock.item.export")
                unlockBenefitRow(icon: "person.2.crop.square.stack", tint: Color(hex: "#F59E0B"), textKey: "premium.carousel.unlock.item.overlay")
                unlockBenefitRow(icon: "sparkles.rectangle.stack", tint: Color(hex: "#22D3EE"), textKey: "premium.carousel.unlock.item.social")
                unlockBenefitRow(
                    icon: "icloud.and.arrow.up",
                    tint: Color(hex: "#A78BFA"),
                    textKey: "premium.carousel.unlock.item.icloud",
                    accessibilityID: "premium.carousel.unlock.item.icloud"
                )
                unlockBenefitRow(icon: "square.grid.2x2", tint: Color(hex: "#94A3B8"), textKey: "premium.carousel.unlock.item.widgets")
                unlockBenefitRow(icon: "flag.fill", tint: Color(hex: "#F43F5E"), textKey: "premium.carousel.unlock.item.support")
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        ClaudeLightStyle.directionalGradient(
                            colors: [Color.white.opacity(0.09), Color.white.opacity(0.04)],
                            colorScheme: colorScheme,
                            lightColor: AppColorRoles.surfaceSecondary,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.16) : AppColorRoles.borderSubtle, lineWidth: 1)
                    )
            )

            trialTimelinePreview
        }
    }

    private var trialTimelinePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.string("premium.trial.timeline.title"))
                .font(AppTypography.captionEmphasis)
                .foregroundStyle(.white.opacity(0.96))

            timelineItem(
                textKey: "premium.trial.timeline.today",
                icon: "sparkles",
                tint: Color(hex: "#FCA311")
            )
            timelineItem(
                textKey: "premium.trial.timeline.day12",
                icon: "bell.badge.fill",
                tint: Color(hex: "#60A5FA")
            )
            timelineItem(
                textKey: "premium.trial.timeline.day14",
                icon: "checkmark.seal.fill",
                tint: Color(hex: "#4ADE80")
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private func timelineItem(textKey: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(tint.opacity(0.22))
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tint)
                )

            Text(AppLocalization.string(textKey))
                .font(AppTypography.micro)
                .foregroundStyle(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
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

        return Button {
            selectedProductID = product.id
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(planTitle(for: product))
                        .font(AppTypography.body)
                        .foregroundStyle(.white.opacity(0.88))
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
            .padding(.bottom, 12)
            .padding(.top, 12)
            .frame(maxWidth: .infinity)
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
    }

    private var subscribeButton: some View {
        Button {
            if premium.isPremium {
                premium.dismissPaywall()
                return
            }
            Task {
                if await premium.activateTrialForUITestsIfNeeded() {
                    return
                }
                guard let product = selectedProduct else { return }
                await premium.purchase(product)
            }
        } label: {
            Text(AppLocalization.string("premium.cta.trial"))
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

            subscribeButton
                .padding(.top, 2)

            Text(AppLocalization.string("premium.cta.free.forever"))
                .font(AppTypography.micro)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

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
        return product.displayName
    }

    private func planSubtitle(for product: PremiumProduct) -> String {
        if isMonthlyPlan(product) {
            return AppLocalization.string("premium.plan.billing.monthly")
        }
        if isYearlyPlan(product) {
            return AppLocalization.string("premium.plan.billing.yearly")
        }
        return AppLocalization.string("premium.plan.billing.default")
    }

    private func primaryPriceLine(for product: PremiumProduct) -> String {
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
        return nil
    }

    private var billedAfterTrialText: Text {
        let product = selectedProduct ?? yearly ?? monthly
        guard let product else {
            return Text(AppLocalization.string("premium.cta.billed.after.trial.fallback"))
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

    @State private var sliderPosition: CGFloat = 0.5
    @State private var isDragging = false

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
