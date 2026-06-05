import SwiftUI
import UIKit

// MARK: - Welcome Step

extension OnboardingView {

    @ViewBuilder
    func onboardingWelcomeSlide(layout: OnboardingCardLayout) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)

            Text(FlowLocalization.app(
                "Track your body change without obsessing over the scale",
                "Śledź zmiany sylwetki bez obsesji na punkcie wagi",
                "Sigue el cambio de tu cuerpo sin obsesionarte con la báscula",
                "Verfolge Körperveränderung ohne Waagen-Obsession",
                "Suivez votre corps sans obsession de la balance",
                "Acompanhe mudanças no corpo sem obsessão pela balança"
            ))
            .font(.system(size: 36, weight: .heavy, design: .rounded))
            .multilineTextAlignment(.center)
            .foregroundStyle(AppColorRoles.textPrimary)
            .padding(.horizontal, 24)

            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.appAccent.opacity(0.28), Color.clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: 110
                            )
                        )
                        .frame(width: 200, height: 200)
                        .blur(radius: 6)
                        .allowsHitTesting(false)

                    MeasureBuddyView(pose: .welcome, size: 150)
                        .shadow(color: Color.appAccent.opacity(0.40), radius: 20, x: 0, y: 14)
                }
                .frame(height: 160)

                MiaraSpeechBubble(
                    text: FlowLocalization.app(
                        "MeasureMe helps you track weight, waist, photos and trends in one private place.",
                        "MeasureMe pomaga śledzić wagę, pas, zdjęcia i trendy w jednym prywatnym miejscu.",
                        "MeasureMe te ayuda a seguir peso, cintura, fotos y tendencias en un lugar privado.",
                        "MeasureMe hilft dir, Gewicht, Taille, Fotos und Trends an einem privaten Ort zu verfolgen.",
                        "MeasureMe vous aide à suivre poids, taille, photos et tendances dans un espace privé.",
                        "O MeasureMe ajuda a acompanhar peso, cintura, fotos e tendências em um lugar privado."
                    )
                )
                .padding(.horizontal, 16)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var introWelcomeVisual: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                ambientBlobs(for: 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                VStack(spacing: 28) {
                    welcomeHeroLogo
                        .opacity(slideAppeared ? 1 : 0)
                        .scaleEffect(slideAppeared ? 1 : 0.85)
                        .animation(shouldAnimate ? AppMotion.sectionEnter.delay(0.1) : .none, value: slideAppeared)

                    VStack(spacing: 8) {
                        Text("MeasureMe")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.appWhite)

                        Text(OnboardingCopy.introSubtitle(index: 0))
                            .font(.system(.title3, design: .rounded).weight(.medium))
                            .foregroundStyle(AppColorRoles.textSecondary)
                            .skeletonShimmer(enabled: welcomeShimmerEnabled)
                    }
                    .multilineTextAlignment(.center)
                    .opacity(slideAppeared ? 1 : 0)
                    .offset(y: slideAppeared ? 0 : 16)
                    .animation(shouldAnimate ? AppMotion.sectionEnter.delay(0.25) : .none, value: slideAppeared)
                }
            }

            Text(FlowLocalization.app(
                "Build a simple body-tracking rhythm around metrics, photos, and insight.",
                "Zbuduj prosty rytm śledzenia ciała wokół metryk, zdjęć i wniosków.",
                "Crea un ritmo simple de seguimiento corporal con métricas, fotos e insights.",
                "Baue einen einfachen Tracking-Rhythmus aus Messwerten, Fotos und Einblicken auf.",
                "Créez un rythme simple autour des mesures, des photos et des insights.",
                "Crie um ritmo simples de acompanhamento com métricas, fotos e insights."
            ))
            .font(AppTypography.body)
            .foregroundStyle(AppColorRoles.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, 32)
            .opacity(slideAppeared ? 1 : 0)
            .animation(shouldAnimate ? AppMotion.sectionEnter.delay(0.4) : .none, value: slideAppeared)

            Spacer()
        }
        .onAppear {
            slideBlobAnimate = true
            if shouldAnimate {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    welcomeShimmerEnabled = false
                }
            } else {
                welcomeShimmerEnabled = false
            }
        }
    }

    var welcomeHeroLogo: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.appAccent.opacity(0.22), Color.appAccent.opacity(0.05), .clear],
                        center: .center, startRadius: 40, endRadius: 160
                    )
                )
                .frame(width: 280, height: 280)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.appAccent.opacity(0.32), .clear],
                        center: .center, startRadius: 30, endRadius: 110
                    )
                )
                .frame(width: 200, height: 200)
                .blur(radius: 10)

            MeasureBuddyView(pose: .welcome, size: 200)
                .shadow(color: Color.appAccent.opacity(0.30), radius: 24, y: 12)
        }
        .accessibilityHidden(true)
    }
}
