import SwiftUI

/// Wspólny nagłówek slajdu onboardingu (tytuł + podtytuł).
/// Używany przez wszystkie kroki (Welcome, Profile, Boosters, Premium).
func onboardingSlideHeader(title: String, subtitle: String, titleSize: CGFloat = 42) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(.system(size: titleSize, weight: .bold, design: .rounded).monospacedDigit())
            // Prefer wrapping over truncation/scaling; onboarding titles should be readable.
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(Color.appWhite)

        if !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(subtitle)
                .font(.system(.title3, design: .rounded).weight(.medium))
                .foregroundStyle(AppColorRoles.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
