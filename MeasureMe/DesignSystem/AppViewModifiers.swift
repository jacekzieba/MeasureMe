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
}
