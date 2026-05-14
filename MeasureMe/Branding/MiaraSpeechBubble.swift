import SwiftUI

/// Dymek dialogowy „Miary" — z prefiksem etykiety u góry.
/// Używany w onboarding (slajd 1 i Premium) oraz wszędzie, gdzie maskotka
/// „mówi" do użytkownika.
struct MiaraSpeechBubble: View {
    let text: String
    var tint: Color = AppColorRoles.accentPrimary
    var maxWidth: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(MeasureBuddyName.display.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColorRoles.textPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background(
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 18, bottomLeading: 4, bottomTrailing: 18, topTrailing: 18),
                style: .continuous
            )
            .fill(tint.opacity(0.07))
            .overlay(
                UnevenRoundedRectangle(
                    cornerRadii: .init(topLeading: 18, bottomLeading: 4, bottomTrailing: 18, topTrailing: 18),
                    style: .continuous
                )
                .stroke(tint.opacity(0.3), lineWidth: 1)
            )
        )
    }
}

#Preview {
    ZStack {
        Color.appInk.ignoresSafeArea()
        VStack(spacing: 24) {
            MiaraSpeechBubble(text: "Cześć! Jestem Miara — pomogę Ci zobaczyć, jak Twoje ciało zmienia się tydzień po tygodniu.")
            MiaraSpeechBubble(text: "Ekipa Miary jest z Tobą. Zaczynajmy 💪", tint: AppColorRoles.chartPositive)
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
