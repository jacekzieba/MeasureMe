import SwiftUI

// MARK: - Ambient Blob Spec

struct AmbientBlobSpec {
    let color: Color
    let innerOpacity: Double
    let outerOpacity: Double
    let size: CGFloat
    let blurRadius: CGFloat
    let startRadius: CGFloat
    let endRadius: CGFloat
    let offsetA: CGSize
    let offsetB: CGSize
}

// MARK: - Ambient Blobs

struct AmbientBlobsView: View {
    let blobs: [AmbientBlobSpec]
    let animate: Bool
    let shouldAnimate: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(blobs.enumerated()), id: \.offset) { _, spec in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [spec.color.opacity(spec.innerOpacity), spec.color.opacity(spec.outerOpacity), .clear],
                                center: .center, startRadius: spec.startRadius, endRadius: spec.endRadius
                            )
                        )
                        .frame(width: spec.size, height: spec.size)
                        .offset(x: animate ? spec.offsetA.width : spec.offsetB.width, y: animate ? spec.offsetA.height : spec.offsetB.height)
                        .blur(radius: spec.blurRadius)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(
                AppMotion.repeating(.easeInOut(duration: 5).repeatForever(autoreverses: true), enabled: shouldAnimate),
                value: animate
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Dummy Line Chart

// MARK: - Dummy Mini Metric Chart Card

struct DummyMiniMetricChartCard: View {
    let title: String
    let value: String
    let delta: String
    let tint: Color
    let backgroundTint: Color
    let points: [CGPoint]
    var targetY: CGFloat? = nil
    var targetX: CGFloat? = nil
    var legends: [DummyChartLegendItem] = []
    var compact = false

    var body: some View {
        ZStack {
            AppGlassBackground(depth: .elevated, cornerRadius: AppRadius.xl, tint: backgroundTint)

            VStack(alignment: .leading, spacing: compact ? 4 : AppSpacing.xs) {
                Text(title)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textSecondary)

                GeometryReader { proxy in
                    ZStack(alignment: .topLeading) {
                        Path { path in
                            for index in 0..<4 {
                                let y = proxy.size.height * CGFloat(index) / 4
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                            }
                        }
                        .stroke(AppColorRoles.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [4, 5]))

                        if let targetY {
                            Path { path in
                                let y = proxy.size.height * targetY
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                            }
                            .stroke(Color.appAccent.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        }

                        Path { path in
                            for (index, point) in points.enumerated() {
                                let resolved = CGPoint(x: proxy.size.width * point.x, y: proxy.size.height * point.y)
                                if index == 0 {
                                    path.move(to: resolved)
                                } else {
                                    path.addLine(to: resolved)
                                }
                            }
                        }
                        .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                        if let targetY, let targetX {
                            Circle()
                                .fill(Color.appAccent)
                                .frame(width: 8, height: 8)
                                .overlay {
                                    Circle()
                                        .stroke(Color.white.opacity(0.7), lineWidth: 2)
                                }
                                .position(x: proxy.size.width * targetX, y: proxy.size.height * targetY)
                        }
                    }
                }
                .frame(height: compact ? IntroMetricsLayout.compactChartHeight : IntroMetricsLayout.chartHeight)

                HStack(spacing: AppSpacing.xs) {
                    if !legends.isEmpty {
                        ForEach(Array(legends.enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 4) {
                                Capsule(style: .continuous)
                                    .fill(item.color)
                                    .frame(width: 12, height: 4)
                                Text(item.label)
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppColorRoles.textSecondary)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: IntroMetricsLayout.legendHeight, alignment: .leading)
                .opacity(legends.isEmpty ? 0 : 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(value)
                        .font(.system(size: compact ? 20 : 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.appWhite)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(delta)
                        .font(.system(size: compact ? 12 : 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: compact ? IntroMetricsLayout.compactValueBlockHeight : IntroMetricsLayout.valueBlockHeight,
                    alignment: .bottomLeading
                )
            }
            .padding(IntroMetricsLayout.cardPadding)
        }
        .frame(maxWidth: .infinity)
        .frame(height: compact ? IntroMetricsLayout.compactChartCardHeight : IntroMetricsLayout.chartCardHeight)
    }
}

// MARK: - Dummy AI Insight Card

struct DummyAIInsightCard: View {
    let title: String
    let lineOne: String
    let lineTwo: String
    let tip: String
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(alignment: .center, spacing: compact ? 8 : 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                    .foregroundStyle(AppColorRoles.accentPrimary)
                    .frame(width: compact ? 26 : 30, height: compact ? 26 : 30)
                    .background(AppColorRoles.accentPrimary.opacity(0.14))
                    .clipShape(Circle())

                Text(title)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
            }

            VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                Text(lineOne)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(lineTwo)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: compact ? 6 : 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .foregroundStyle(AppColorRoles.accentPrimary)
                    .padding(.top, 1)

                Text(tip)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.accentPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(AppColorRoles.accentPrimary.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .stroke(AppColorRoles.accentPrimary.opacity(0.24), lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, compact ? AppSpacing.sm : AppSpacing.smmd)
        .padding(.vertical, compact ? 10 : 12)
        .background {
            AppGlassBackground(depth: .base, cornerRadius: 20, tint: AppColorRoles.accentPrimary.opacity(0.05))
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Before/After Slider

struct OnboardingBeforeAfterSlider: View {
    let beforeImageName: String
    let afterImageName: String
    let beforeLabel: String
    let afterLabel: String
    let imageAlignment: Alignment
    let shouldAnimateHint: Bool

    @State private var sliderPosition: CGFloat = 0.5
    @State private var isDragging = false
    @State private var hasInteracted = false
    @State private var hasPlayedHintAnimation = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            let clampedSlider = min(max(sliderPosition, 0), 1)

            ZStack {
                AppColorRoles.surfaceChrome.opacity(0.86)

                onboardingPhoto(beforeImageName, width: width, height: height)

                onboardingPhoto(afterImageName, width: width, height: height)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: width * clampedSlider)
                    }

                LinearGradient(
                    colors: [
                        .black.opacity(0.24),
                        .clear,
                        .black.opacity(0.42)
                    ],
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
                .padding(AppSpacing.smmd)
                .frame(maxHeight: .infinity, alignment: .bottom)

                sliderHandle(height: height)
                    .position(x: width * clampedSlider, y: height / 2)

                if !hasInteracted {
                    VStack {
                        BeforeAfterSliderInteractionHint()
                            .padding(.top, 12)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.appAccent.opacity(0.38), lineWidth: 1)
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

    private func onboardingPhoto(_ imageName: String, width: CGFloat, height: CGFloat) -> some View {
        Image(imageName)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height, alignment: imageAlignment)
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
                .frame(width: isDragging ? 52 : 46, height: isDragging ? 52 : 46)
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

// MARK: - Dummy Indicator Card

struct DummyIndicatorCard: View {
    let title: String
    let value: String
    let legend: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(tint.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay {
                    Circle()
                        .fill(tint)
                        .frame(width: 14, height: 14)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
                Text(legend)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
            }

            Spacer()

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.appWhite)
        }
        .padding(18)
        .background(
            AppGlassBackground(depth: .base, cornerRadius: 22, tint: tint)
        )
    }
}

// MARK: - Onboarding Silhouette

// MARK: - Onboarding Confetti View
