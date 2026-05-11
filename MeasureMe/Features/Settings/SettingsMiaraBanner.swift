import SwiftUI

/// Banner z Miarą na górze ekranu Ustawień — sygnał, że to miejsce,
/// w którym dostosowujemy aplikację razem.
struct SettingsMiaraBanner: View {
    var body: some View {
        HStack(spacing: 11) {
            MeasureBuddyView(pose: .settings, size: 48, idleAnimation: false)

            VStack(alignment: .leading, spacing: 2) {
                Text(FlowLocalization.app(
                    "Customize MeasureMe",
                    "Dostosuj MeasureMe",
                    "Personaliza MeasureMe",
                    "MeasureMe anpassen",
                    "Personnaliser MeasureMe",
                    "Personalize o MeasureMe"
                ))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(AppColorRoles.textPrimary)

                Text(FlowLocalization.app(
                    "Tell Miara how to take care of you — theme, units, reminders.",
                    "Powiedz Miarze, jak ma się Tobą zająć — motyw, jednostki, przypomnienia.",
                    "Dile a Miara cómo cuidar de ti — tema, unidades, recordatorios.",
                    "Sag Miara, wie sie sich um dich kümmern soll — Theme, Einheiten, Erinnerungen.",
                    "Dis à Miara comment prendre soin de toi — thème, unités, rappels.",
                    "Diga à Miara como cuidar de você — tema, unidades, lembretes."
                ))
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(AppColorRoles.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                )
        )
    }
}
