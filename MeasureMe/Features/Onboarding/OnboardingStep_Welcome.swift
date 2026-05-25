import SwiftUI
import UIKit

// MARK: - Welcome Step

private extension OnboardingView {

    @ViewBuilder
    func onboardingWelcomeSlide(layout: OnboardingCardLayout) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)

            Text(FlowLocalization.app(
                "Welcome to\nMeasureMe",
                "Witaj w\nMeasureMe",
                "Bienvenido a\nMeasureMe",
                "Willkommen bei\nMeasureMe",
                "Bienvenue dans\nMeasureMe",
                "Bem-vindo ao\nMeasureMe"
            ))
            .font(.system(size: 40, weight: .heavy))
            .tracking(-1.0)
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
                        "Hey, I'm Miara. I'll be here every week to show you how your body is actually changing. No scale drama, no shame, just a clear picture.",
                        "Hej, jestem Miara. Będę pokazywać, jak naprawdę zmienia się Twoje ciało. Bez skupiania się tylko na wadze i bez oceniania. Tylko jasny obraz.",
                        "Hola, soy Miara. Cada semana te mostraré cómo está cambiando tu cuerpo de verdad. Sin drama de báscula y sin juicios. Solo una imagen clara.",
                        "Hey, ich bin Miara. Jede Woche zeige ich dir, wie sich dein Körper wirklich verändert. Kein Waagen-Drama, kein Urteil. Nur ein klares Bild.",
                        "Salut, c'est Miara. Chaque semaine, je te montre comment ton corps évolue vraiment. Sans drame de balance, sans jugement. Juste une image claire.",
                        "Oi, sou a Miara. Toda semana vou te mostrar como seu corpo está mudando de verdade. Sem drama da balança, sem julgamento. Só uma imagem clara."
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
