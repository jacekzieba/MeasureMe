import SwiftUI

enum AppCTAButtonSize {
    case compact
    case regular
    case large

    var verticalPadding: CGFloat {
        switch self {
        case .compact: return 8
        case .regular: return 10
        case .large: return 12
        }
    }

    var font: Font {
        switch self {
        case .compact: return .system(.subheadline, design: .rounded).weight(.semibold)
        case .regular: return .system(.headline, design: .rounded).weight(.semibold)
        case .large: return .system(.headline, design: .rounded).weight(.bold)
        }
    }
}

struct AppCTAButtonStyle: ButtonStyle {
    var size: AppCTAButtonSize = .regular
    var cornerRadius: CGFloat = AppRadius.md
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true

    private struct CTAButtonVisuals: ViewModifier {
        var size: AppCTAButtonSize
        var cornerRadius: CGFloat
        var animationsEnabled: Bool
        var isPressed: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.isEnabled) private var isEnabled

        func body(content: Content) -> some View {
            let shouldAnimate = AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
            content
                .font(size.font)
                .foregroundStyle(AppColorRoles.textOnAccent)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, size.verticalPadding)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            colorScheme == .dark
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [
                                            AppColorRoles.accentGradientStart,
                                            AppColorRoles.accentGradientMid,
                                            AppColorRoles.accentGradientEnd
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                : AnyShapeStyle(
                                    AppColorRoles.accentPrimary
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(colorScheme == .dark ? 0.12 : 0.18),
                                            Color.white.opacity(colorScheme == .dark ? 0.02 : 0.04),
                                            .clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(
                                    colorScheme == .dark
                                        ? AnyShapeStyle(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.28),
                                                    AppColorRoles.borderStrong.opacity(0.68)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        : AnyShapeStyle(Color(hex: "#D7950D")),
                                    lineWidth: 1
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .inset(by: 0.5)
                                .stroke(
                                    colorScheme == .dark
                                        ? Color.clear
                                        : Color.white.opacity(0.20),
                                    lineWidth: 0.6
                                )
                        )
                )
                .scaleEffect(isPressed && shouldAnimate ? 0.98 : 1)
                .opacity(isEnabled ? 1 : 0.55)
                .shadow(color: colorScheme == .dark ? Color.appAccent.opacity(isPressed ? 0.16 : 0.24) : AppColorRoles.shadowStrong.opacity(isPressed ? 0.05 : 0.10), radius: isPressed ? 4 : 12, x: 0, y: isPressed ? 2 : 6)
                .shadow(color: colorScheme == .dark ? .clear : AppColorRoles.shadowSoft.opacity(0.16), radius: 2, x: 0, y: 1)
                .animation(AppMotion.animation(AppMotion.quick, enabled: shouldAnimate), value: isPressed)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(CTAButtonVisuals(size: size, cornerRadius: cornerRadius, animationsEnabled: animationsEnabled, isPressed: configuration.isPressed))
    }
}

struct AppSecondaryButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = AppRadius.md
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true

    private struct SecondaryButtonVisuals: ViewModifier {
        var cornerRadius: CGFloat
        var animationsEnabled: Bool
        var isPressed: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.isEnabled) private var isEnabled

        func body(content: Content) -> some View {
            let shouldAnimate = AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
            content
                .font(.system(.subheadline, design: .default).weight(.medium))
                .foregroundStyle(AppColorRoles.textPrimary)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            colorScheme == .dark
                                ? AnyShapeStyle(AppColorRoles.surfaceChrome)
                                : AnyShapeStyle(
                                    AppColorRoles.surfaceSecondary
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(colorScheme == .dark ? 0.02 : 0.48),
                                            Color.white.opacity(colorScheme == .dark ? 0.01 : 0.14),
                                            Color.clear
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(
                                    colorScheme == .dark
                                        ? AnyShapeStyle(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.16),
                                                    AppColorRoles.borderStrong.opacity(1)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        : AnyShapeStyle(AppColorRoles.borderSubtle.opacity(isPressed ? 1 : 0.96)),
                                    lineWidth: 1
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .inset(by: 0.5)
                                .stroke(
                                    colorScheme == .dark
                                        ? Color.clear
                                        : Color.white.opacity(0.58),
                                    lineWidth: 0.6
                                )
                        )
                )
                .scaleEffect(isPressed && shouldAnimate ? 0.98 : 1)
                .opacity(isEnabled ? 1 : 0.52)
                .shadow(color: colorScheme == .dark ? AppColorRoles.shadowSoft.opacity(isPressed ? 0.24 : 0.34) : AppColorRoles.shadowSoft.opacity(isPressed ? 0.05 : 0.10), radius: isPressed ? 4 : 8, x: 0, y: isPressed ? 2 : 4)
                .animation(AppMotion.animation(AppMotion.quick, enabled: shouldAnimate), value: isPressed)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(SecondaryButtonVisuals(cornerRadius: cornerRadius, animationsEnabled: animationsEnabled, isPressed: configuration.isPressed))
    }
}

struct AppDestructiveButtonStyle: ButtonStyle {
    var size: AppCTAButtonSize = .regular
    var cornerRadius: CGFloat = AppRadius.md
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        _AnimatedButtonContent(
            isPressed: configuration.isPressed,
            animationsEnabled: animationsEnabled,
            label: {
                configuration.label
                    .font(size.font)
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, size.verticalPadding)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.red)
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .stroke(AppColorRoles.borderStrong, lineWidth: 1)
                            )
                    )
            },
            shadow: { shouldAnimate in
                AnyView(
                    EmptyView()
                        .scaleEffect(configuration.isPressed && shouldAnimate ? 0.98 : 1)
                        .shadow(
                            color: Color.red.opacity(configuration.isPressed ? 0.14 : 0.24),
                            radius: configuration.isPressed ? 4 : 9,
                            x: 0,
                            y: configuration.isPressed ? 1 : 3
                        )
                )
            }
        )
    }
}

struct AppInputContainerStyle: ViewModifier {
    var focused: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [
                                    AppColorRoles.surfaceSecondary.opacity(0.92),
                                    AppColorRoles.surfaceInteractive.opacity(0.92)
                                ]
                                : [
                                    AppColorRoles.surfacePrimary,
                                    AppColorRoles.surfaceSecondary,
                                    AppColorRoles.surfaceInteractive
                                ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .dark ? 0.05 : 0.34),
                                        focused ? Color.appAccent.opacity(colorScheme == .dark ? 0.10 : 0.08) : .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                            .stroke(
                                focused ? Color.appAccent.opacity(colorScheme == .dark ? 0.68 : 0.44) : AppColorRoles.borderSubtle,
                                lineWidth: 1
                            )
                    )
            )
    }
}

struct AppMetricCardStyle: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(AppSpacing.sm)
            .background(
                AppGlassBackground(
                    depth: .base,
                    cornerRadius: cornerRadius,
                    tint: Color.clear
                )
            )
    }
}

private struct _AnimatedButtonContent<Label: View>: View {
    let isPressed: Bool
    let animationsEnabled: Bool
    let label: () -> Label
    let shadow: (_ shouldAnimate: Bool) -> AnyView
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shouldAnimate = AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
        label()
            .overlay(
                shadow(shouldAnimate)
            )
            .animation(AppMotion.animation(AppMotion.quick, enabled: shouldAnimate), value: isPressed)
    }
}

extension View {
    func appInputContainer(focused: Bool = false) -> some View {
        modifier(AppInputContainerStyle(focused: focused))
    }

    func appMetricCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(AppMetricCardStyle(cornerRadius: cornerRadius))
    }
}
