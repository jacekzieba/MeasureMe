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

    /// Use for generated or user-provided copy whose full value must remain visible.
    func appUntruncatedText() -> some View {
        modifier(AppUntruncatedTextModifier())
    }
}
