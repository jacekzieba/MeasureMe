import SwiftUI

private struct AppSectionSpacingModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(.vertical, AppSpacing.xs)
    }
}

private struct AppCardPaddingModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(AppSpacing.sm)
    }
}

private struct AppHitTargetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// A button that spans the width of a phone would stretch into a bar across a wide screen (an
/// open iPhone Duo), so at regular width it keeps a phone-like width, centred in its row.
private struct AppAdaptiveButtonWidthModifier: ViewModifier {
    static let maxRegularWidth: CGFloat = 360

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content
                .frame(maxWidth: Self.maxRegularWidth)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

private struct AppUntruncatedTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
    }
}

extension View {
    func appSectionSpacing() -> some View {
        modifier(AppSectionSpacingModifier())
    }

    func appCardPadding() -> some View {
        modifier(AppCardPaddingModifier())
    }

    func appHitTarget() -> some View {
        modifier(AppHitTargetModifier())
    }

    /// Apply to a full-width button (one whose label uses `.frame(maxWidth: .infinity)`).
    func appAdaptiveButtonWidth() -> some View {
        modifier(AppAdaptiveButtonWidthModifier())
    }

    /// Use for generated or user-provided copy whose full value must remain visible.
    func appUntruncatedText() -> some View {
        modifier(AppUntruncatedTextModifier())
    }
}
