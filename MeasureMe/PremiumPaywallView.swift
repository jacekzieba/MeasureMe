import SwiftUI
import StoreKit
import UIKit

struct PremiumPaywallView: View {
    @EnvironmentObject private var premium: PremiumStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedProductID: String?
    @State private var selectedSlide: Int = 0
    @State private var isCTAPulsing: Bool = false
    @AppStorage("animationsEnabled") private var animationsEnabled: Bool = true
    @AppStorage("userName") private var userName: String = ""

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

    private var availableProducts: [Product] {
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

    private var carouselHeight: CGFloat {
        465
    }

    private var yearlySavingsPercent: Int? {
        guard let monthly, let yearly else { return nil }
        let yearlyFromMonthly = monthly.price * Decimal(12)
        guard yearlyFromMonthly > 0 else { return nil }
        let savings = (yearlyFromMonthly - yearly.price) / yearlyFromMonthly
        guard savings > 0 else { return nil }
        let percent = NSDecimalNumber(decimal: savings * Decimal(100)).doubleValue
        return Int(percent.rounded())
    }

    private var shouldAnimateCTA: Bool {
        animationsEnabled && !reduceMotion
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
        case .en:
            return false
        case .system:
            return Locale.preferredLanguages.first?.lowercased().hasPrefix("pl") ?? false
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AppScreenBackground(topHeight: 430, tint: currentSlide.tint.opacity(0.24))

            ScrollView {
                VStack(spacing: 14) {
                    Text(AppLocalization.string("Premium Edition"))
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    carousel
                    pageIndicator
                    purchaseDock
                }
                .padding(.top, 20)
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }

            Button {
                premium.dismissPaywall()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.14))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            }
            .padding(.top, 12)
            .padding(.trailing, 16)
            .accessibilityLabel(AppLocalization.string("accessibility.close.premium.paywall"))
            .accessibilityHint(AppLocalization.string("accessibility.close.premium.paywall.hint"))
        }
        .onAppear {
            premium.clearActionMessage()
            Task { await premium.loadProducts() }
            if selectedProductID == nil {
                selectedProductID = PremiumConstants.yearlyProductID
            }
            if shouldAnimateCTA {
                isCTAPulsing = true
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
                premium.dismissPaywall()
            }
        }
        .onChange(of: shouldAnimateCTA) { _, shouldAnimate in
            isCTAPulsing = shouldAnimate
        }
    }

    private var carousel: some View {
        TabView(selection: $selectedSlide) {
            ForEach(slides) { slide in
                VStack(spacing: 10) {
                    headerRow(for: slide)

                    if slide.kind != .unlock {
                        featureDescriptionCard(for: slide)
                    }
                    slideContentSeparator

                    supplementaryContent(for: slide)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: slide.gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                )
                .tag(slide.id)
            }
        }
        .frame(height: carouselHeight)
        .animation(.easeInOut(duration: 0.2), value: selectedSlide)
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(slides) { slide in
                Capsule(style: .continuous)
                    .fill(slide.id == selectedSlide ? Color.white : Color.white.opacity(0.28))
                    .frame(width: slide.id == selectedSlide ? 18 : 7, height: 7)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedSlide)
    }

    private func featureDescriptionCard(for slide: PremiumSlide) -> some View {
        Text(AppLocalization.string(slide.bodyKey))
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.95))
            .multilineTextAlignment(.leading)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [slide.tint.opacity(0.26), Color.white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
    }

    private var slideContentSeparator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.18))
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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                )

            Text(AppLocalization.string(slide.titleKey))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
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
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "#FCA311"))
                    )

                Text(AppLocalization.string("premium.carousel.insight.header"))
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.white.opacity(0.92))
            }

            Text(aiInsightAttributedText)
            .font(AppTypography.captionEmphasis)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "#FDE68A"))

                Text(AppLocalization.string("premium.carousel.insight.tip"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(Color(hex: "#FBBF24"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: "#3A2A1C").opacity(0.62))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(hex: "#FBBF24").opacity(0.28), lineWidth: 1)
                    )
            )

            if isPolishInterface {
                Text(AppLocalization.string("premium.carousel.insight.language.note"))
                    .font(AppTypography.micro)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#1E2850").opacity(0.85), Color.black.opacity(0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        )
    }

    private var aiInsightAttributedText: AttributedString {
        var text = AttributedString()

        if let name = personalizedFirstName {
            var namePart = AttributedString("\(name), ")
            namePart.foregroundColor = Color(hex: "#FCA311")
            text += namePart
        }

        var part1 = AttributedString(AppLocalization.string("premium.carousel.insight.body.part1"))
        part1.foregroundColor = Color.white.opacity(0.92)
        text += part1

        var valuePart = AttributedString(" -0.3 kg/week ")
        valuePart.foregroundColor = Color(hex: "#22C55E")
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
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.24))

                VStack(spacing: 10) {
                    comparisonPoseGridRow(label: AppLocalization.string("premium.compare.when.past"), silhouetteOpacity: 0.72)
                    comparisonPoseGridRow(label: AppLocalization.string("premium.compare.when.present"), silhouetteOpacity: 0.94)
                }
                .padding(12)

                Rectangle()
                    .fill(Color.white.opacity(0.24))
                    .frame(width: 1.5)
                    .padding(.vertical, 14)

                Circle()
                    .fill(Color(hex: "#F5A623"))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.black.opacity(0.7))
                    )
            }
            .frame(height: 210)

                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.and.right.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(AppLocalization.string("premium.compare.when.past"))
                    Text("↔")
                    Text(AppLocalization.string("premium.compare.when.present"))
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

    private func comparisonPoseGridRow(label: String, silhouetteOpacity: Double) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(AppTypography.microEmphasis)
                .foregroundStyle(.white.opacity(0.84))
                .frame(width: 38, alignment: .leading)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                comparisonPoseCard(title: AppLocalization.string("premium.compare.pose.front"), silhouetteOpacity: silhouetteOpacity)
                comparisonPoseCard(title: AppLocalization.string("premium.compare.pose.side"), silhouetteOpacity: silhouetteOpacity)
                comparisonPoseCard(title: AppLocalization.string("premium.compare.pose.back"), silhouetteOpacity: silhouetteOpacity)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func comparisonPoseCard(title: String, silhouetteOpacity: Double) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )

                VStack(spacing: 4) {
                    Circle()
                        .fill(Color.white.opacity(silhouetteOpacity))
                        .frame(width: 10, height: 10)
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(silhouetteOpacity))
                        .frame(width: 14, height: 24)
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(silhouetteOpacity * 0.88))
                        .frame(width: 18, height: 5)
                }
            }
            .frame(height: 56)

            Text(title)
                .font(AppTypography.micro)
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
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
                tint: Color(hex: "#22C55E")
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
                    .background(Color(hex: "#22C55E"), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                        .foregroundStyle(.white.opacity(0.92))
                }

                unlockBenefitRow(icon: "sparkles", tint: Color(hex: "#4ADE80"), textKey: "premium.carousel.unlock.item.ai")
                unlockBenefitRow(icon: "photo.on.rectangle.angled", tint: Color(hex: "#60A5FA"), textKey: "premium.carousel.unlock.item.compare")
                unlockBenefitRow(icon: "heart.text.square.fill", tint: Color(hex: "#34D399"), textKey: "premium.carousel.unlock.item.health")
                unlockBenefitRow(icon: "doc.text.fill", tint: Color(hex: "#FBBF24"), textKey: "premium.carousel.unlock.item.export")
            }
            .padding(10)
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

            trialTimelinePreview

            HStack(spacing: 8) {
                Text(AppLocalization.string("premium.carousel.unlock.item.support"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
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

    private func unlockBenefitRow(icon: String, tint: Color, textKey: String) -> some View {
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
    }

    private var planPicker: some View {
        VStack(spacing: 12) {
            if availableProducts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(Color.appAccent)
                        Text(AppLocalization.string("premium.subscription.loading"))
                            .font(AppTypography.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    if let error = premium.productsLoadError {
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
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
            } else {
                ForEach(availableProducts, id: \.id) { product in
                    planRow(product: product)
                }
            }
        }
    }

    private func planRow(product: Product) -> some View {
        let isSelected = product.id == selectedProductID
        let subtitle = planSubtitle(for: product)
        let badge = planBadge(for: product)

        return Button {
            selectedProductID = product.id
        } label: {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(planTitle(for: product))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                        Text(subtitle)
                            .font(AppTypography.caption)
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(priceLine(for: product))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.9)

                        if product.id == PremiumConstants.yearlyProductID,
                           let yearlySavingsPercent {
                            Text(AppLocalization.string("premium.plan.save.percent", yearlySavingsPercent))
                                .font(AppTypography.micro)
                                .foregroundStyle(.white.opacity(0.64))
                        }
                    }
                    .padding(.top, badge == nil ? 0 : 16)
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

                if let badge {
                    Text(badge.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.92))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.appAccent)
                        )
                        .offset(y: -9)
                        .padding(.trailing, 10)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var subscribeButton: some View {
        Button {
            if premium.isPremium {
                premium.dismissPaywall()
                return
            }
            guard let product = selectedProduct else { return }
            Task { await premium.purchase(product) }
        } label: {
            Text(AppLocalization.string("premium.cta.trial"))
        }
        .buttonStyle(AppAccentButtonStyle(cornerRadius: 30))
        .disabled(!premium.isPremium && selectedProduct == nil)
        .scaleEffect(shouldAnimateCTA ? (isCTAPulsing ? 1.0 : 0.975) : 1.0)
        .shadow(
            color: Color.appAccent.opacity(shouldAnimateCTA ? (isCTAPulsing ? 0.48 : 0.24) : 0.18),
            radius: shouldAnimateCTA ? (isCTAPulsing ? 16 : 9) : 7,
            x: 0,
            y: 0
        )
        .animation(
            shouldAnimateCTA ? .easeInOut(duration: 1.25).repeatForever(autoreverses: true) : .default,
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
                        : Color(hex: "#22C55E")
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
        let privacyURL = URL(string: "https://jacekzieba.pl/privacy.html")
        let termsURL = URL(string: "https://jacekzieba.pl/terms.html")

        return HStack(spacing: 22) {
            if let privacyURL {
                Link(AppLocalization.string("Privacy"), destination: privacyURL)
            } else {
                Text(AppLocalization.string("Privacy"))
            }
            Button(AppLocalization.string("Restore purchases")) {
                Task { await premium.restorePurchases() }
            }
            if let termsURL {
                Link(AppLocalization.string("Terms"), destination: termsURL)
            } else {
                Text(AppLocalization.string("Terms"))
            }
        }
        .font(AppTypography.captionEmphasis)
        .foregroundStyle(Color.appAccent)
        .padding(.top, 4)
    }

    private func planTitle(for product: Product) -> String {
        switch product.id {
        case PremiumConstants.monthlyProductID:
            return AppLocalization.string("premium.plan.monthly")
        case PremiumConstants.yearlyProductID:
            return AppLocalization.string("premium.plan.yearly")
        default:
            return product.displayName
        }
    }

    private func planSubtitle(for product: Product) -> String {
        switch product.id {
        case PremiumConstants.monthlyProductID:
            return AppLocalization.string("premium.plan.billing.monthly")
        case PremiumConstants.yearlyProductID:
            return AppLocalization.string("premium.plan.billing.yearly")
        default:
            return AppLocalization.string("premium.plan.billing.default")
        }
    }

    private func planBadge(for product: Product) -> String? {
        guard product.id == PremiumConstants.yearlyProductID else { return nil }
        return AppLocalization.string("premium.plan.best.value")
    }

    private func priceLine(for product: Product) -> String {
        switch product.id {
        case PremiumConstants.monthlyProductID:
            return "\(product.displayPrice)/\(AppLocalization.string("premium.plan.period.month"))"
        case PremiumConstants.yearlyProductID:
            let monthlyEquivalent = product.price / Decimal(12)
            let monthlyEquivalentDisplay = monthlyEquivalent.formatted(product.priceFormatStyle)
            return AppLocalization.string("premium.plan.just.monthly.dynamic", monthlyEquivalentDisplay)
        default:
            return product.displayPrice
        }
    }

    private var billedAfterTrialText: Text {
        let product = selectedProduct ?? yearly ?? monthly
        guard let product else {
            return Text(AppLocalization.string("premium.cta.billed.after.trial.fallback"))
        }

        let periodLabel: String
        if product.id == PremiumConstants.yearlyProductID {
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
}
