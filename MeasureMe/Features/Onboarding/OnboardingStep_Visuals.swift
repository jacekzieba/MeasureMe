import SwiftUI
import UIKit

// MARK: - Step Visuals (Photos, Health, Privacy)

extension OnboardingView {

    func introPhotosVisual(layout: OnboardingCardLayout) -> some View {
        let beforeLabel = FlowLocalization.app("Before", "Przed", "Antes", "Vorher", "Avant", "Antes")
        let afterLabel = FlowLocalization.app("After", "Po", "Después", "Nachher", "Après", "Depois")
        let compareLabel = FlowLocalization.app("Compare", "Porównaj", "Comparar", "Vergleichen", "Comparer", "Comparar")
        let isRecomp = resolvedPriority == .improveHealth
        let photoWidth = isRecomp ? layout.photoWidth + (layout.isCompact ? 24 : 34) : layout.photoWidth
        let photoHeight = isRecomp ? layout.photoHeight + (layout.isCompact ? 24 : 34) : layout.photoHeight

        return VStack(spacing: 12) {
            OnboardingBeforeAfterSlider(
                // The "Before" / "After" assets were authored flipped; swap at the call site.
                beforeImageName: onboardingAfterAssetName,
                afterImageName: onboardingBeforeAssetName,
                beforeLabel: beforeLabel,
                afterLabel: afterLabel,
                imageAlignment: isRecomp ? .center : .top,
                shouldAnimateHint: shouldAnimate
            )
            .frame(width: photoWidth, height: photoHeight)
            .frame(maxWidth: .infinity)
            .opacity(photoAfterAppeared ? 1 : 0)
            .offset(y: photoAfterAppeared ? 0 : 18)
            .animation(shouldAnimate ? AppMotion.sectionEnter.delay(0.25) : .none, value: photoAfterAppeared)

            Capsule(style: .continuous)
                .fill(AppColorRoles.surfaceChrome.opacity(0.92))
                .frame(width: layout.compareChipWidth, height: layout.compareChipHeight)
                .overlay {
                    HStack(spacing: 10) {
                        Image(systemName: "camera.metering.none")
                        Text(compareLabel)
                    }
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textPrimary)
                }
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.appAccent.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: AppColorRoles.shadowSoft.opacity(0.16), radius: 12, y: 6)
        }
        .onAppear {
            if shouldAnimate {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    photoAfterAppeared = true
                }
            } else {
                photoAfterAppeared = true
            }
        }
    }

    func photoCard(imageName: String, label: String, borderColor: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.5)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                Text(label)
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                    .padding(.bottom, AppSpacing.smmd)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
        }
    }

    var introHealthVisual: some View {
        let cards: [(String, String, String, Color)] = [
            ("Waist-to-Height", "0.47", "On track", AppColorRoles.stateSuccess),
            ("Body Fat", "18%", "On track", Color.appAccent),
            ("Shoulder-to-Waist", "1.52", "Strong", Color(hex: "#F59E0B"))
        ]
        return VStack(spacing: 14) {
            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                DummyIndicatorCard(title: card.0, value: card.1, legend: card.2, tint: card.3)
                    .opacity(healthCardsAppeared ? 1 : 0)
                    .offset(y: healthCardsAppeared ? 0 : 20)
                    .animation(shouldAnimate ? AppMotion.sectionEnter.delay(Double(index) * 0.15 + 0.1) : .none, value: healthCardsAppeared)
            }
        }
        .onAppear {
            if shouldAnimate {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    healthCardsAppeared = true
                }
            } else {
                healthCardsAppeared = true
            }
        }
    }

    var introPrivacyVisual: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule(style: .continuous)
                .fill(Color.appAccent.opacity(0.18))
                .frame(width: 118, height: 34)
                .overlay {
                    Text(FlowLocalization.app(
                        "On-device",
                        "Na urządzeniu",
                        "En el dispositivo",
                        "Auf dem Gerät",
                        "Sur l'appareil",
                        "No dispositivo"
                    ))
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(Color.appAccent)
                }

            ZStack {
                AppGlassBackground(depth: .elevated, cornerRadius: 26, tint: Color.appAccent)
                VStack(spacing: 18) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(Color.appAccent)
                        .shadow(color: Color.appAccent.opacity(shieldGlowPhase ? 0.4 : 0.1), radius: 20)
                        .animation(
                            AppMotion.repeating(.easeInOut(duration: 1.25).repeatForever(autoreverses: true), enabled: shouldAnimate),
                            value: shieldGlowPhase
                        )
                    Text(FlowLocalization.app(
                        "Private by design",
                        "Prywatność od podstaw",
                        "Privacidad por diseño",
                        "Datenschutz by design",
                        "Confidentialité par conception",
                        "Privacidade desde a origem"
                    ))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.appWhite)
                    Text(FlowLocalization.app(
                        "Your photos and measurements never leave your device.",
                        "Twoje zdjęcia i pomiary nigdy nie opuszczają urządzenia.",
                        "Tus fotos y medidas nunca salen de tu dispositivo.",
                        "Deine Fotos und Messwerte verlassen dein Gerät nie.",
                        "Vos photos et mesures ne quittent jamais votre appareil.",
                        "Suas fotos e medições nunca saem do seu dispositivo."
                    ))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                }
            }
            .frame(height: 220)
            .onAppear { shieldGlowPhase = true }
        }
    }
}
