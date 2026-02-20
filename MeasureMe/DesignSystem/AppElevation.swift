import SwiftUI

enum AppElevation {
    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    static let card = Shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 5)
    static let floating = Shadow(color: .black.opacity(0.24), radius: 14, x: 0, y: 8)
    static let overlay = Shadow(color: .black.opacity(0.30), radius: 18, x: 0, y: 10)
}

private struct AppShadowModifier: ViewModifier {
    let shadow: AppElevation.Shadow

    func body(content: Content) -> some View {
        content.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

extension View {
    func appElevation(_ shadow: AppElevation.Shadow) -> some View {
        modifier(AppShadowModifier(shadow: shadow))
    }
}
