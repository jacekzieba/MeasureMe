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
/// open iPhone Duo), so in a wide row it keeps a phone-like width, centred in the row. A row of
/// `buttons` side by side gets that width per button, so the row stays together. The row's width is
/// measured rather than read from the size class: a sheet on the open Duo is ~650 pt wide yet
/// reports a compact width.
private struct AppAdaptiveButtonWidthModifier: ViewModifier {
    static let maxRegularWidth: CGFloat = 360
    static let minimumCappedRowWidth: CGFloat = 600

    let buttons: Int
    let spacing: CGFloat

    @State private var rowWidth: CGFloat = 0

    func body(content: Content) -> some View {
        let count = CGFloat(max(buttons, 1))
        let cap = Self.maxRegularWidth * count + spacing * (count - 1)
        content
            .frame(maxWidth: rowWidth >= Self.minimumCappedRowWidth ? cap : .infinity)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
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

    /// Apply to a full-width button (one whose label uses `.frame(maxWidth: .infinity)`), or to a
    /// row of `buttons` such buttons `spacing` apart.
    func appAdaptiveButtonWidth(buttons: Int = 1, spacing: CGFloat = 0) -> some View {
        modifier(AppAdaptiveButtonWidthModifier(buttons: buttons, spacing: spacing))
    }

    /// Use for generated or user-provided copy whose full value must remain visible.
    func appUntruncatedText() -> some View {
        modifier(AppUntruncatedTextModifier())
    }
}
