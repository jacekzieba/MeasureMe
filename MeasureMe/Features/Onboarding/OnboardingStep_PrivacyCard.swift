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
        .accessibilityIdentifier("onboarding.privacy.note")
    }
}
