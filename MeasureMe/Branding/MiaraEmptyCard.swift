import SwiftUI

/// Wspólny widok empty-state z maskotką: dashed card, mascot 140pt,
/// cytat-tytuł, podtytuł i CTA. Używany dla Photos, Home (no measurements)
/// i Goals (no goal).
struct MiaraEmptyCard: View {
    let pose: MeasureBuddy
    let title: String
    let subtitle: String
    let ctaTitle: String
    let onTap: () -> Void
    var mascotSize: CGFloat = 140
    var tint: Color = AppColorRoles.accentPrimary

    var body: some View {
        VStack(spacing: 12) {
            MeasureBuddyView(pose: pose, size: mascotSize)
                .shadow(color: tint.opacity(0.25), radius: 12, x: 0, y: 12)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColorRoles.textPrimary)
                .frame(maxWidth: 230)

            Text(subtitle)
                .font(.system(size: 11, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColorRoles.textSecondary)
                .lineSpacing(2)
                .frame(maxWidth: 230)
                .padding(.bottom, 6)

            Button(action: onTap) {
                Text(ctaTitle)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(AppColorRoles.textOnAccent)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(tint)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 22)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            AppColorRoles.borderSubtle,
                            style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                        )
                )
        )
    }
}

#Preview {
    ZStack {
        Color.appInk.ignoresSafeArea()
        MiaraEmptyCard(
            pose: .thumbs,
            title: "„Pierwsze zdjęcie to start Twojej historii.”",
            subtitle: "Zrób je dziś, a za miesiąc będzie czego porównywać. Przebierać się nie trzeba — wystarczy ten sam kąt.",
            ctaTitle: "Zrób pierwsze zdjęcie",
            onTap: {}
        )
        .padding()
    }
    .preferredColorScheme(.dark)
}
