// AppGlass.swift
//
// **AppGlass**
// "Glass" / "liquid" visual treatment primitives — the design-system language
// used by the app's premium surfaces (cards, buttons, segmented controls, etc.).
//
// **Responsibilities:**
// - Defining depth tokens (`AppGlassDepth`) with associated shadow/highlight
//   opacities so all glass surfaces feel visually consistent
// - Providing `AppGlassBackground` and `AppGlassCard` as the canonical
//   background + content wrapper
// - Exposing button / toggle / segmented-control styles built on the same
//   visual language
// - Adapting every effect for dark vs. light mode (no gradient overlays in
//   light mode to preserve readability)
//
// **Why one file, not one-per-type:**
// The depth tokens, the card wrapper, and the button/toggle styles are tightly
// coupled — a redesign of one almost always means a redesign of the others.
// Keeping them together makes the system easier to evolve as a unit.
//
import SwiftUI

// MARK: - Light-mode style adapter

/// Helpers that downgrade the glass visual treatment in light mode.
///
/// In light mode, the gradient overlays and tints that define the dark-mode
/// "glass" look become noise that hurts readability. These helpers collapse
/// gradients to a flat fill and soften tints so the same component reads well
/// in both appearances.
enum ClaudeLightStyle {
    /// Returns a directional gradient in dark mode, a flat color in light mode.
    /// - Parameters:
    ///   - colors: Colors to use in dark mode (the first color is reused
    ///     for the flat light-mode fill).
    ///   - colorScheme: Current appearance.
    ///   - lightColor: Optional override for the flat light-mode fill.
    ///   - startPoint: Gradient start anchor.
    ///   - endPoint: Gradient end anchor.
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

        // In light mode collapse the gradient to a single fill to keep the
        // surface flat and legible.
        let resolvedLightColor = lightColor ?? colors.first ?? .clear
        return LinearGradient(
            colors: [resolvedLightColor, resolvedLightColor],
            startPoint: startPoint,
            endPoint: endPoint
        )
    }

    /// Returns a tinted area fill — gradient fade in dark mode, flat alpha
    /// in light mode.
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

    /// Returns the accent at the right opacity for the current appearance.
    static func tintOverlay(accent: Color, colorScheme: ColorScheme, lightOpacity: Double, darkOpacity: Double) -> Color {
        accent.opacity(colorScheme == .dark ? darkOpacity : lightOpacity)
    }
}

// MARK: - Depth tokens

/// Three depth levels for glass surfaces, each defining the full set of
/// shadow / highlight opacities so cards at the same depth look identical.
enum AppGlassDepth {
    /// Default depth for in-content cards.
    case base
    /// Cards that float above other content (e.g. active sheets).
    case elevated
    /// Cards at the topmost layer (e.g. modal alerts, popovers).
    case floating

    /// Opacity of the white highlight on the top edge in dark mode.
    var highlightOpacity: Double {
        switch self {
        case .base: return 0.14
        case .elevated: return 0.18
        case .floating: return 0.24
        }
    }

    /// Opacity of the inner-edge black stroke in dark mode.
    var innerEdgeOpacity: Double {
        switch self {
        case .base: return 0.22
        case .elevated: return 0.26
        case .floating: return 0.30
        }
    }

    /// Opacity of the dark-mode darkness overlay painted on top of the fill.
    var darkness: Double {
        switch self {
        case .base: return 0.36
        case .elevated: return 0.28
        case .floating: return 0.20
        }
    }

    /// Strength of the accent tint applied to the surface.
    var tintStrength: Double {
        switch self {
        case .base: return 0.10
        case .elevated: return 0.13
        case .floating: return 0.16
        }
    }

    /// Drop-shadow opacity (combined with the design-system shadow color).
    var shadowOpacity: Double {
        switch self {
        case .base: return 0.18
        case .elevated: return 0.24
        case .floating: return 0.30
        }
    }

    /// Drop-shadow blur radius in points.
    var shadowRadius: CGFloat {
        switch self {
        case .base: return 10
        case .elevated: return 14
        case .floating: return 18
        }
    }

    /// Drop-shadow vertical offset in points.
    var shadowY: CGFloat {
        switch self {
        case .base: return 5
        case .elevated: return 8
        case .floating: return 10
        }
    }
}

// MARK: - Glass background

/// Rounded glass surface — the base building block for cards, sheets, and pills.
///
/// The exact stack of overlays differs between dark and light mode; see
/// `baseBackground` for the order of overlays that defines the look.
struct AppGlassBackground: View {
    /// Depth token (controls shadow and highlight opacities).
    var depth: AppGlassDepth = .base
    /// Corner radius in points.
    var cornerRadius: CGFloat = 16
    /// Accent tint applied to the surface (`.clear` for a neutral surface).
    var tint: Color = .clear
    /// When `false`, drop shadows are omitted (useful when the card is already
    /// sitting on a strongly-shadowed parent and would otherwise look "doubled").
    var showsShadow: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    /// Base fill — `.ultraThinMaterial` in dark mode (so the wallpaper shows
    /// through subtly), a flat semantic surface in light mode.
    private var backgroundFill: AnyShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(.ultraThinMaterial)
            : AnyShapeStyle(AppColorRoles.surfacePrimary)
    }

    /// Diagonal white gradient overlaid in dark mode to give the surface a
    /// top-lit appearance. In light mode the gradient is fully transparent.
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

    /// Stroke used to give the surface a defined edge — bright in dark mode,
    /// a subtle border in light mode.
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

    /// Inner black stroke (dark mode only) — sits just inside the border
    /// to give the surface an "etched" feel.
    private var innerStrokeColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(depth.innerEdgeOpacity)
            : .clear
    }

    /// Resolved drop-shadow color, blended with the depth's opacity.
    private var shadowColor: Color {
        (colorScheme == .dark ? AppColorRoles.shadowStrong : AppColorRoles.shadowSoft)
            .opacity(depth.shadowOpacity)
    }

    /// Rounded-rectangle shape used everywhere a stroke or fill is needed.
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// Tint gradient overlay — stronger at the top-left, fading toward the
    /// bottom-right. Empty in light mode.
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

    /// Dark-mode-only darkness wash used to mute the material under the
    /// gradient overlays.
    @ViewBuilder
    private var fillOverlay: some View {
        if colorScheme == .dark {
            shape.fill(Color.black.opacity(depth.darkness))
        }
    }

    /// Top-edge highlight stroke.
    @ViewBuilder
    private var highlightStroke: some View {
        if colorScheme == .dark {
            shape.stroke(Color.white.opacity(depth.highlightOpacity), lineWidth: 1)
        } else {
            shape.stroke(AppColorRoles.borderSubtle, lineWidth: 1)
        }
    }

    /// Strong border stroke applied to every glass surface.
    private var borderStroke: some View {
        shape.stroke(
            colorScheme == .dark
                ? AppColorRoles.borderStrong.opacity(0.66)
                : AppColorRoles.borderStrong.opacity(0.90),
            lineWidth: 1
        )
    }

    /// Inner 0.5pt black stroke (dark mode) inset from the border.
    private var innerStroke: some View {
        shape
            .inset(by: 0.5)
            .stroke(innerStrokeColor, lineWidth: 0.8)
    }

    /// The full overlay stack. Order matters:
    /// 1. background fill, 2. tint, 3. darkness, 4. border, 5. highlight, 6. inner edge.
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
                // Light mode keeps only the fill + border — no gradients or
                // darkness overlay, for legibility.
                shape
                    .fill(backgroundFill)
                    .overlay(borderStroke)
            }
        }
    }

    var body: some View {
        if showsShadow {
            // Dark-mode shadows are larger and stronger than light-mode ones;
            // the 0.6 / 0.55 multipliers make the effect consistent visually.
            baseBackground
                .shadow(color: shadowColor, radius: depth.shadowRadius * (colorScheme == .dark ? 1.0 : 0.6), x: 0, y: depth.shadowY * (colorScheme == .dark ? 1.0 : 0.55))
                .shadow(color: colorScheme == .dark ? .clear : AppColorRoles.shadowSoft.opacity(0.08), radius: 1, x: 0, y: 1)
        } else {
            baseBackground
        }
    }
}

// MARK: - Glass card

/// Padded content wrapper backed by an `AppGlassBackground`.
///
/// Use this instead of stacking a `.padding()` + `.background()` yourself so
/// the visual treatment stays consistent across the app.
struct AppGlassCard<Content: View>: View {
    let depth: AppGlassDepth
    let cornerRadius: CGFloat
    let tint: Color
    let showsShadow: Bool
    let contentPadding: CGFloat
    @ViewBuilder let content: Content

    /// - Parameters:
    ///   - depth: Depth token (default `.base`).
    ///   - cornerRadius: Corner radius (default `18`).
    ///   - tint: Accent tint (default `.clear`).
    ///   - showsShadow: Whether to draw a drop shadow (default `true`).
    ///   - contentPadding: Internal padding around `content` (default `14`).
    ///   - content: The view to wrap in the glass card.
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

// MARK: - Liquid button style

/// Pill-shaped button with the same glass visual language used by cards.
/// Reads as a "chip" in the UI.
struct LiquidCapsuleButtonStyle: ButtonStyle {
    /// Accent color of the tint.
    var tint: Color = .appAccent
    /// Foreground color of the button's label.
    var textColor: Color = AppColorRoles.textPrimary
    @AppSetting(\.experience.animationsEnabled) private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        // Respect the user's "reduce motion" accessibility setting; pressing
        // should not scale the button when motion is reduced.
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

// MARK: - Liquid switch

/// Custom switch toggle styled to match the glass visual language.
///
/// The switch is implemented as a `Button` so VoiceOver announces a
/// single tappable region; the actual binding flip happens inside the button.
struct LiquidSwitchToggleStyle: ToggleStyle {
    /// Accent color of the switch's "on" state.
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

// MARK: - Photo tag chip

/// Toggle styled as a pill-shaped "chip" used by photo tagging filters.
/// Fires selection haptic when toggled on.
struct PhotoTagChipToggleStyle: ToggleStyle {
    /// Accent color of the chip's active state.
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

// MARK: - Segmented control glass modifier

/// View modifier that wraps a `Picker` (or any capsule-shaped segmented
/// control) in the glass visual treatment.
struct GlassSegmentedControlModifier: ViewModifier {
    /// Accent color used for the tint overlay.
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
    /// Applies the glass segmented control treatment to the receiver.
    /// - Parameter tint: Accent color used for the tint overlay.
    func glassSegmentedControl(tint: Color = .appAccent) -> some View {
        modifier(GlassSegmentedControlModifier(tint: tint))
    }
}
