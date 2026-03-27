import SwiftUI

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
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundFill: AnyShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(.ultraThinMaterial)
            : AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(hex: "#E6E6E3").opacity(0.99),
                        Color(hex: "#E0E0DD").opacity(0.99),
                        Color(hex: "#D6D6D3").opacity(0.99)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var fillOverlayGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(0.48),
                    Color.white.opacity(0.20)
                ]
                : [
                    Color.white.opacity(0.06),
                    Color(hex: "#E4E4E1").opacity(0.10),
                    Color(hex: "#D7D7D3").opacity(0.14)
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
                    Color.white.opacity(0.14),
                    AppColorRoles.borderStrong.opacity(0.42)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var innerStrokeColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(depth.innerEdgeOpacity)
            : AppColorRoles.borderSubtle.opacity(0.88)
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
                    tint.opacity(max(depth.tintStrength * 0.42, 0.03)),
                    Color.white.opacity(0.03),
                    Color(hex: "#D9D9D5").opacity(0.06)
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
        } else {
            shape.fill(fillOverlayGradient)
            shape.fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.02),
                        tint.opacity(max(depth.tintStrength * 0.20, 0.025)),
                        Color.black.opacity(0.028),
                        .clear
                    ],
                    center: .topLeading,
                    startRadius: 8,
                    endRadius: cornerRadius * 7
                )
            )
        }
    }

    @ViewBuilder
    private var highlightStroke: some View {
        if colorScheme == .dark {
            shape.stroke(Color.white.opacity(depth.highlightOpacity), lineWidth: 1)
        } else {
            shape.stroke(highlightStrokeGradient, lineWidth: 1)
        }
    }

    private var borderStroke: some View {
        shape.stroke(
            colorScheme == .dark
                ? AppColorRoles.borderStrong.opacity(0.66)
                : AppColorRoles.borderStrong.opacity(0.84),
            lineWidth: 1
        )
    }

    private var innerStroke: some View {
        shape
            .inset(by: 0.5)
            .stroke(innerStrokeColor, lineWidth: 0.8)
    }

    var body: some View {
        shape
            .fill(backgroundFill)
            .overlay(tintedOverlay)
            .overlay(fillOverlay)
            .overlay(borderStroke)
            .overlay(highlightStroke)
            .overlay(innerStroke)
            .shadow(
                color: .clear,
                radius: 0,
                x: 0,
                y: 0
            )
            .shadow(
                color: shadowColor,
                radius: depth.shadowRadius * (colorScheme == .dark ? 1.0 : 1.3),
                x: 0,
                y: depth.shadowY * (colorScheme == .dark ? 1.0 : 1.2)
            )
    }
}

struct AppGlassCard<Content: View>: View {
    let depth: AppGlassDepth
    let cornerRadius: CGFloat
    let tint: Color
    let contentPadding: CGFloat
    @ViewBuilder let content: Content

    init(
        depth: AppGlassDepth = .base,
        cornerRadius: CGFloat = 18,
        tint: Color = .clear,
        contentPadding: CGFloat = 14,
        @ViewBuilder content: () -> Content
    ) {
        self.depth = depth
        self.cornerRadius = cornerRadius
        self.tint = tint
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
                    tint: tint
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
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(colorScheme == .dark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.thinMaterial))
                    .overlay(Capsule().fill(tint.opacity(configuration.isPressed ? 0.28 : 0.22)))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                colorScheme == .dark
                                    ? Color.white.opacity(configuration.isPressed ? 0.32 : 0.22)
                                    : AppColorRoles.borderStrong.opacity(configuration.isPressed ? 1 : 0.84),
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
            )
            .scaleEffect(configuration.isPressed && shouldAnimate ? 0.98 : 1)
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
                        .fill(colorScheme == .dark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.thinMaterial))
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
                    .fill(colorScheme == .dark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.thinMaterial))
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
                    .fill(colorScheme == .dark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.thinMaterial))
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
