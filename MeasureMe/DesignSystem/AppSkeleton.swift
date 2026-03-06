import SwiftUI

struct SkeletonBlock: View {
    var cornerRadius: CGFloat = AppRadius.sm
    var opacity: Double = 0.14

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(opacity))
    }
}

struct SkeletonShimmerModifier: ViewModifier {
    let enabled: Bool
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if enabled {
                    GeometryReader { proxy in
                        let width = max(proxy.size.width, 1)
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.20),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: width * 0.65)
                        .offset(x: phase * width * 1.7)
                        .blendMode(.plusLighter)
                        .onAppear {
                            guard phase == -1 else { return }
                            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                                phase = 1
                            }
                        }
                    }
                    .allowsHitTesting(false)
                    .clipShape(Rectangle())
                }
            }
    }
}

extension View {
    func skeletonShimmer(enabled: Bool) -> some View {
        modifier(SkeletonShimmerModifier(enabled: enabled))
    }
}
