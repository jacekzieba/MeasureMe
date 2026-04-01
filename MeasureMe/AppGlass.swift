import SwiftUI

enum ClaudeLightStyle {
    static func directionalGradient(
        colors: [Color],
        colorScheme: ColorScheme,
        lightColor: Color? = nil,
        startPoint: UnitPoint = .topLeading,
        endPoint: UnitPoint = .bottomTrailing
    ) -> LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: colors,
                startPoint: startPoint,
                endPoint: endPoint
            )
        }

        let resolvedLightColor = lightColor ?? colors.first ?? .clear
        return LinearGradient(
            colors: [resolvedLightColor, resolvedLightColor],
            startPoint: startPoint,
            endPoint: endPoint
        )
    }

    static func areaFill(accent: Color, colorScheme: ColorScheme) -> AnyShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        accent.opacity(0.28),
                        accent.opacity(0.02)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }

        return AnyShapeStyle(accent.opacity(0.10))
    }

    static func tintOverlay(accent: Color, colorScheme: ColorScheme, lightOpacity: Double, darkOpacity: Double) -> Color {
        accent.opacity(colorScheme == .dark ? darkOpacity : lightOpacity)
    }
}

enum AppGlassDepth {
    case base
    case elevated
    case floating

    var highlightOpacity: Double {
        switch self {
        case .base: return 0.14
        case .elevated: return 0.18
        case .floating: return 0.24
        }
    }

    var innerEdgeOpacity: Double {
        switch self {
        case .base: return 0.22
        case .elevated: return 0.26
        case .floating: return 0.30
        }
    }

    var darkness: Double {
        switch self {
        case .base: return 0.36
        case .elevated: return 0.28
        case .floating: return 0.20
        }
    }

    var tintStrength: Double {
        switch self {
        case .base: return 0.10
        case .elevated: return 0.13
        case .floating: return 0.16
        }
    }

    var shadowOpacity: Double {
        switch self {
        case .base: return 0.18
        case .elevated: return 0.24
        case .floating: return 0.30
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .base: return 10
        case .elevated: return 14
        case .floating: return 18
        }
    }

    var shadowY: CGFloat {
        switch self {
        case .base: return 5
        case .elevated: return 8
        case .floating: return 10
        }
    }
}

struct AppGlassBackground: View {
    var depth: AppGlassDepth = .base
    var cornerRadius: CGFloat = 16
    var tint: Color = .clear
    var showsShadow: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundFill: AnyShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(.ultraThinMaterial)
            : AnyShapeStyle(AppColorRoles.surfacePrimary)
    }

    private var fillOverlayGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(0.48),
                    Color.white.opacity(0.20)
                ]
                : [
                    .clear,
                    .clear
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var highlightStrokeGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(0.68),
                    AppColorRoles.borderStrong.opacity(0.50)
                ]
                : [
                    AppColorRoles.borderSubtle,
                    AppColorRoles.borderSubtle
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var innerStrokeColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(depth.innerEdgeOpacity)
            : .clear
    }

    private var shadowColor: Color {
        (colorScheme == .dark ? AppColorRoles.shadowStrong : AppColorRoles.shadowSoft)
            .opacity(depth.shadowOpacity)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var tintedOverlay: some View {
        shape.fill(
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        tint.opacity(depth.tintStrength),
                        tint.opacity(depth.tintStrength * 0.42),
                        tint.opacity(depth.tintStrength * 0.16)
                    ]
                : [
                    .clear,
                    .clear,
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    @ViewBuilder
    private var fillOverlay: some View {
        if colorScheme == .dark {
            shape.fill(Color.black.opacity(depth.darkness))
        }
    }

    @ViewBuilder
    private var highlightStroke: some View {
        if colorScheme == .dark {
            shape.stroke(Color.white.opacity(depth.highlightOpacity), lineWidth: 1)
        } else {
            shape.stroke(AppColorRoles.borderSubtle, lineWidth: 1)
        }
    }

    private var borderStroke: some View {
        shape.stroke(
            colorScheme == .dark
                ? AppColorRoles.borderStrong.opacity(0.66)
                : AppColorRoles.borderStrong.opacity(0.90),
            lineWidth: 1
        )
    }

    private var innerStroke: some View {
        shape
            .inset(by: 0.5)
            .stroke(innerStrokeColor, lineWidth: 0.8)
    }

    private var baseBackground: some View {
        Group {
            if colorScheme == .dark {
                shape
                    .fill(backgroundFill)
                    .overlay(tintedOverlay)
                    .overlay(fillOverlay)
                    .overlay(borderStroke)
                    .overlay(highlightStroke)
                    .overlay(innerStroke)
            } else {
                shape
                    .fill(backgroundFill)
                    .overlay(borderStroke)
            }
        }
    }

    var body: some View {
        if showsShadow {
            baseBackground
                .shadow(color: shadowColor, radius: depth.shadowRadius * (colorScheme == .dark ? 1.0 : 0.6), x: 0, y: depth.shadowY * (colorScheme == .dark ? 1.0 : 0.55))
                .shadow(color: colorScheme == .dark ? .clear : AppColorRoles.shadowSoft.opacity(0.08), radius: 1, x: 0, y: 1)
        } else {
            baseBackground
        }
    }
}

struct AppGlassCard<Content: View>: View {
    let depth: AppGlassDepth
    let cornerRadius: CGFloat
    let tint: Color
    let showsShadow: Bool
    let contentPadding: CGFloat
    @ViewBuilder let content: Content

    init(
        depth: AppGlassDepth = .base,
        cornerRadius: CGFloat = 18,
        tint: Color = .clear,
        showsShadow: Bool = true,
        contentPadding: CGFloat = 14,
        @ViewBuilder content: () -> Content
    ) {
        self.depth = depth
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.showsShadow = showsShadow
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(contentPadding)
            .background(
                AppGlassBackground(
                    depth: depth,
                    cornerRadius: cornerRadius,
                    tint: tint,
                    showsShadow: showsShadow
                )
            )
    }
}

struct LiquidCapsuleButtonStyle: ButtonStyle {
    var tint: Color = .appAccent
    var textColor: Color = AppColorRoles.textPrimary
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let shouldAnimate = animationsEnabled && !reduceMotion
        configuration.label
            .font(.system(.subheadline, design: .default).weight(.semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? AnyShapeStyle(.ultraThinMaterial)
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: [
                                        AppColorRoles.surfaceSecondary,
                                        AppColorRoles.surfaceInteractive
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(Capsule().fill(tint.opacity(colorScheme == .dark ? (configuration.isPressed ? 0.28 : 0.22) : (configuration.isPressed ? 0.14 : 0.10))))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                colorScheme == .dark
                                    ? Color.white.opacity(configuration.isPressed ? 0.32 : 0.22)
                                    : AppColorRoles.borderSubtle.opacity(configuration.isPressed ? 1 : 0.96),
                                lineWidth: 1
                            )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .inset(by: 0.5)
                            .stroke(
                                colorScheme == .dark
                                    ? Color.black.opacity(0.24)
                                    : Color.white.opacity(0.62),
                                lineWidth: 0.6
                            )
                    )
            )
            .scaleEffect(configuration.isPressed && shouldAnimate ? 0.98 : 1)
            .shadow(color: colorScheme == .dark ? .clear : AppColorRoles.shadowSoft.opacity(configuration.isPressed ? 0.06 : 0.10), radius: configuration.isPressed ? 4 : 8, x: 0, y: configuration.isPressed ? 2 : 4)
    }
}

struct LiquidSwitchToggleStyle: ToggleStyle {
    var tint: Color = .appAccent
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 8)
            Button {
                configuration.isOn.toggle()
            } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule(style: .continuous)
                        .fill(
                            colorScheme == .dark
                                ? AnyShapeStyle(.ultraThinMaterial)
                                : AnyShapeStyle(
                                    LinearGradient(
                                        colors: [
                                            AppColorRoles.surfaceElevated,
                                            AppColorRoles.surfaceGlass
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(Capsule().fill(tint.opacity(configuration.isOn ? 0.32 : 0.14)))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(
                                    colorScheme == .dark
                                        ? Color.white.opacity(0.18)
                                        : AppColorRoles.borderStrong.opacity(0.8),
                                    lineWidth: 1
                                )
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .inset(by: 0.5)
                                .stroke(
                                    colorScheme == .dark
                                        ? Color.black.opacity(0.24)
                                        : Color.white.opacity(0.55),
                                    lineWidth: 0.6
                                )
                        )
                        .frame(width: 52, height: 32)

                    Circle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.95) : Color.white)
                        .frame(width: 26, height: 26)
                        .padding(3)
                        .shadow(color: AppColorRoles.shadowSoft.opacity(0.9), radius: 2.5, x: 0, y: 1.5)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(configuration.isOn ? AppLocalization.string("accessibility.toggle.on") : AppLocalization.string("accessibility.toggle.off"))
        }
    }
}

struct PhotoTagChipToggleStyle: ToggleStyle {
    var tint: Color = .appAccent
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let shouldAnimate = animationsEnabled && !reduceMotion
        let foregroundColor = configuration.isOn ? AppColorRoles.textOnAccent : AppColorRoles.textPrimary

        Button {
            configuration.isOn.toggle()
            Haptics.selection()
        } label: {
            HStack(spacing: AppSpacing.xxs) {
                if configuration.isOn {
                    Image(systemName: "checkmark")
                        .font(AppTypography.microBold)
                }
                configuration.label
                    .font(AppTypography.captionEmphasis)
                    .lineLimit(1)
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? AnyShapeStyle(.ultraThinMaterial)
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: [
                                        AppColorRoles.surfaceElevated,
                                        AppColorRoles.surfaceGlass,
                                        AppColorRoles.surfacePrimary
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .fill(tint.opacity(configuration.isOn ? 0.88 : 0.14))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .stroke(
                                colorScheme == .dark
                                    ? Color.white.opacity(configuration.isOn ? 0.34 : 0.18)
                                    : AppColorRoles.borderStrong.opacity(configuration.isOn ? 1 : 0.78),
                                lineWidth: 1
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .inset(by: 0.5)
                            .stroke(
                                colorScheme == .dark
                                    ? Color.black.opacity(configuration.isOn ? 0.12 : 0.24)
                                    : Color.white.opacity(0.55),
                                lineWidth: 0.6
                            )
                    )
            )
            .shadow(
                color: tint.opacity(configuration.isOn ? 0.34 : 0.0),
                radius: configuration.isOn ? 8 : 0,
                x: 0,
                y: configuration.isOn ? 3 : 0
            )
            .scaleEffect(configuration.isOn && shouldAnimate ? 1.01 : 1)
        }
        .buttonStyle(.plain)
    }
}

struct GlassSegmentedControlModifier: ViewModifier {
    var tint: Color = .appAccent
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(4)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? AnyShapeStyle(.ultraThinMaterial)
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: [
                                        AppColorRoles.surfaceSecondary,
                                        AppColorRoles.surfaceInteractive
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(Capsule().fill(tint.opacity(colorScheme == .dark ? 0.10 : 0.18)))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.16)
                                    : AppColorRoles.borderStrong.opacity(0.78),
                                lineWidth: 1
                            )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .inset(by: 0.5)
                            .stroke(
                                colorScheme == .dark
                                    ? Color.black.opacity(0.22)
                                    : Color.white.opacity(0.55),
                                lineWidth: 0.6
                            )
                    )
            )
    }
}

extension View {
    func glassSegmentedControl(tint: Color = .appAccent) -> some View {
        modifier(GlassSegmentedControlModifier(tint: tint))
    }
}
