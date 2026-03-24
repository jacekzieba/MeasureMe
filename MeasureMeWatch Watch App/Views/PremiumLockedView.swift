import SwiftUI

struct PremiumLockedView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.watchAccent)
                .accessibilityHidden(true)

            Text(String(localized: "Premium Feature", table: "Watch"))
                .font(.headline)
                .foregroundStyle(.white)

            Text(String(localized: "Upgrade to Premium on your iPhone to use MeasureMe on Apple Watch.", table: "Watch"))
                .font(.caption2)
                .foregroundStyle(Color.watchSubtleText)
                .multilineTextAlignment(.center)
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}
