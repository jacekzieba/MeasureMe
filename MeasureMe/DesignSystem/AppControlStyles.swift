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
    @AppStorage("animationsEnabled") private var animationsEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        _AnimatedButtonContent(
            isPressed: configuration.isPressed,
            animationsEnabled: animationsEnabled,
            label: {
                configuration.label
                    .font(size.font)
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, size.verticalPadding)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.appAccent)
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                            )
                    )
            },
            shadow: { shouldAnimate in
                AnyView(
                    EmptyView()
                        .scaleEffect(configuration.isPressed && shouldAnimate ? 0.98 : 1)
                        .shadow(
                            color: Color.appAccent.opacity(configuration.isPressed ? 0.14 : 0.24),
                            radius: configuration.isPressed ? 4 : 9,
                            x: 0,
                            y: configuration.isPressed ? 1 : 3
                        )
                )
            }
        )
    }
}

struct AppSecondaryButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = AppRadius.md
    @AppStorage("animationsEnabled") private var animationsEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        _AnimatedButtonContent(
            isPressed: configuration.isPressed,
            animationsEnabled: animationsEnabled,
            label: {
                configuration.label
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.appWhite)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .fill(Color.appAccent.opacity(configuration.isPressed ? 0.18 : 0.12))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                            )
                    )
            },
            shadow: { shouldAnimate in
                AnyView(
                    EmptyView()
                        .scaleEffect(configuration.isPressed && shouldAnimate ? 0.98 : 1)
                )
            }
        )
    }
}

struct AppDestructiveButtonStyle: ButtonStyle {
    var size: AppCTAButtonSize = .regular
    var cornerRadius: CGFloat = AppRadius.md
    @AppStorage("animationsEnabled") private var animationsEnabled: Bool = true

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
                                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
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

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(AppColorRoles.surfaceSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                            .stroke(Color.white.opacity(focused ? 0.36 : 0.16), lineWidth: 1)
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
