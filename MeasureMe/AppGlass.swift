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

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.opacity(depth.tintStrength))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(depth.darkness))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(depth.highlightOpacity), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .inset(by: 0.5)
                    .stroke(Color.black.opacity(depth.innerEdgeOpacity), lineWidth: 0.7)
            )
            .shadow(color: .black.opacity(depth.shadowOpacity), radius: depth.shadowRadius, x: 0, y: depth.shadowY)
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
    var textColor: Color = .white
    @AppStorage("animationsEnabled") private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let shouldAnimate = animationsEnabled && !reduceMotion
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(tint.opacity(configuration.isPressed ? 0.22 : 0.16)))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(configuration.isPressed ? 0.32 : 0.22), lineWidth: 1)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .inset(by: 0.5)
                            .stroke(Color.black.opacity(0.24), lineWidth: 0.6)
                    )
            )
            .scaleEffect(configuration.isPressed && shouldAnimate ? 0.98 : 1)
    }
}

struct LiquidSwitchToggleStyle: ToggleStyle {
    var tint: Color = .appAccent

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 8)
            Button {
                configuration.isOn.toggle()
            } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().fill(tint.opacity(configuration.isOn ? 0.24 : 0.08)))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .inset(by: 0.5)
                                .stroke(Color.black.opacity(0.24), lineWidth: 0.6)
                        )
                        .frame(width: 52, height: 32)

                    Circle()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: 26, height: 26)
                        .padding(3)
                        .shadow(color: .black.opacity(0.22), radius: 2.5, x: 0, y: 1.5)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(configuration.isOn ? AppLocalization.string("accessibility.toggle.on") : AppLocalization.string("accessibility.toggle.off"))
        }
    }
}

struct GlassSegmentedControlModifier: ViewModifier {
    var tint: Color = .appAccent

    func body(content: Content) -> some View {
        content
            .padding(4)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(tint.opacity(0.10)))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .inset(by: 0.5)
                            .stroke(Color.black.opacity(0.22), lineWidth: 0.6)
                    )
            )
    }
}

extension View {
    func glassSegmentedControl(tint: Color = .appAccent) -> some View {
        modifier(GlassSegmentedControlModifier(tint: tint))
    }
}
