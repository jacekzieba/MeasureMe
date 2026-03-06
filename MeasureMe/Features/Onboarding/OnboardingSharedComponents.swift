import SwiftUI

/// Wspólny nagłówek slajdu onboardingu (tytuł + podtytuł).
/// Używany przez wszystkie kroki (Welcome, Profile, Boosters, Premium).
func onboardingSlideHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
            .minimumScaleFactor(0.72)
            .lineLimit(2)
            .foregroundStyle(Color.appWhite)

        if !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(subtitle)
                .font(.system(.title3, design: .rounded).weight(.medium))
                .foregroundStyle(Color.appGray)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
