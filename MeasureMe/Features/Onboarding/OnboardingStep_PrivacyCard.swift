import SwiftUI
import UIKit

// MARK: - Privacy Card

extension OnboardingView {

    func privacyCard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(alignment: .top, spacing: compact ? 8 : 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: compact ? 16 : 18, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
                    .frame(width: compact ? 30 : 34, height: compact ? 30 : 34)
                    .background(Color.appAccent.opacity(0.16))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        FlowLocalization.app(
                            "Private by design",
                            "Prywatność od podstaw",
                            "Privacidad desde el diseño",
                            "Datenschutz von Anfang an",
                            "Confidentialité par conception",
                            "Privacidade desde a origem"
                        )
                    )
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)

                    Text(
                        FlowLocalization.app(
                            "Your photos and measurements never leave your device.",
                            "Twoje zdjęcia i pomiary nigdy nie opuszczają urządzenia.",
                            "Tus fotos y medidas nunca salen de tu dispositivo.",
                            "Deine Fotos und Messwerte verlassen dein Gerät nie.",
                            "Vos photos et mesures ne quittent jamais votre appareil.",
                            "Suas fotos e medições nunca saem do seu dispositivo."
                        )
                    )
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(compact ? 0.82 : 0.9)
                    .allowsTightening(true)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
            }

            Text(
                FlowLocalization.app(
                    "AI summaries run on device where available, and Apple Health access stays optional.",
                    "Podsumowania AI działają na urządzeniu tam, gdzie są dostępne, a dostęp do Apple Health pozostaje opcjonalny.",
                    "Los resúmenes de IA se ejecutan en el dispositivo cuando están disponibles y el acceso a Apple Health sigue siendo opcional.",
                    "KI-Zusammenfassungen laufen, wo verfügbar, auf dem Gerät und Apple Health bleibt optional.",
                    "Les résumés IA fonctionnent sur l'appareil lorsqu'ils sont disponibles, et l'accès à Apple Health reste facultatif.",
                    "Os resumos de IA rodam no aparelho quando disponíveis, e o acesso ao Apple Health continua opcional."
                )
            )
            .font(AppTypography.microEmphasis)
            .foregroundStyle(Color.appAccent)
            .lineLimit(2)
            .minimumScaleFactor(compact ? 0.72 : 0.78)
            .allowsTightening(true)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)

            Divider()
                .overlay(AppColorRoles.borderSubtle)

            analyticsConsentRow(compact: compact)
        }
        .padding(compact ? AppSpacing.sm : AppSpacing.smmd)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(AppColorRoles.surfaceInteractive)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
                )
        )
        .accessibilityIdentifier("onboarding.privacy.card")
    }

    /// Explicit, opt-in analytics consent. Defaults to off, and no signal is sent until
    /// onboarding completes — see `analyticsConsentDecided`.
    @ViewBuilder
    func analyticsConsentRow(compact: Bool) -> some View {
        let title = FlowLocalization.app(
            "Share anonymous usage stats",
            "Udostępniaj anonimowe statystyki użycia",
            "Compartir estadísticas de uso anónimas",
            "Anonyme Nutzungsstatistiken teilen",
            "Partager des statistiques d'usage anonymes",
            "Compartilhar estatísticas de uso anônimas"
        )
        let subtitle = FlowLocalization.app(
            "Off by default. Never your measurements or photos — you can change this any time in Settings.",
            "Domyślnie wyłączone. Nigdy Twoje pomiary ani zdjęcia — możesz to zmienić w Ustawieniach.",
            "Desactivado por defecto. Nunca tus medidas ni fotos: puedes cambiarlo en Ajustes.",
            "Standardmäßig aus. Nie deine Messwerte oder Fotos – jederzeit in den Einstellungen änderbar.",
            "Désactivé par défaut. Jamais vos mesures ni vos photos — modifiable à tout moment dans Réglages.",
            "Desativado por padrão. Nunca suas medições ou fotos — dá para mudar nos Ajustes."
        )

        HStack(alignment: .top, spacing: compact ? 8 : 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)

                Text(subtitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .minimumScaleFactor(compact ? 0.8 : 0.9)
                    .allowsTightening(true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            Toggle("", isOn: $analyticsEnabled)
                .labelsHidden()
                .frame(width: 52, alignment: .trailing)
                .tint(Color.appAccent)
                .accessibilityLabel(title)
                .accessibilityValue(analyticsEnabled ? AppLocalization.string("Enabled") : AppLocalization.string("Disabled"))
        }
        .accessibilityIdentifier("onboarding.privacy.analyticsToggle")
    }
}
