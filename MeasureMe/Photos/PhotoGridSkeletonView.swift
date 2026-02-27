import SwiftUI

struct PhotoGridSkeletonView: View {
    var itemCount: Int = 12

    @AppStorage("animationsEnabled") private var animationsEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldShimmer: Bool {
        AppMotion.shouldAnimate(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 110), spacing: 8)],
            spacing: 8
        ) {
            ForEach(0..<itemCount, id: \.self) { _ in
                SkeletonBlock(cornerRadius: 12, opacity: 0.16)
                    .frame(width: 110, height: 120)
                    .skeletonShimmer(enabled: shouldShimmer)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading photos")
    }
}
