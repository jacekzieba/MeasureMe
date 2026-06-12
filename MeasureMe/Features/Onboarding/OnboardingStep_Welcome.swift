import SwiftUI
import UIKit

// MARK: - Welcome Step

extension OnboardingView {

    @ViewBuilder
    func onboardingWelcomeSlide(layout: OnboardingCardLayout) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            welcomeProofCard
                .padding(.horizontal, 20)

            VStack(spacing: 10) {
                Text(FlowLocalization.app(
                    "See change, week after week",
                    "Zobacz zmianę, tydzień po tygodniu",
                    "Mira el cambio, semana tras semana",
                    "Sieh Veränderung, Woche für Woche",
                    "Voyez le changement, semaine après semaine",
                    "Veja a mudança, semana após semana"
                ))
                .font(.system(size: layout.isCompact ? 30 : 34, weight: .heavy, design: .rounded))
                .tracking(-0.5)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColorRoles.textPrimary)

                Text(FlowLocalization.app(
                    "Measurements, photos and trends — all stay on your device.",
                    "Pomiary, zdjęcia i trendy — wszystko zostaje na Twoim urządzeniu.",
                    "Medidas, fotos y tendencias: todo se queda en tu dispositivo.",
                    "Messwerte, Fotos und Trends – alles bleibt auf deinem Gerät.",
                    "Mesures, photos et tendances — tout reste sur votre appareil.",
                    "Medições, fotos e tendências — tudo fica no seu aparelho."
                ))
                .font(AppTypography.body)
                .foregroundStyle(AppColorRoles.textSecondary)
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            HStack(alignment: .bottom, spacing: 12) {
                MeasureBuddyView(pose: .welcome, size: 76)
                    .shadow(color: Color.appAccent.opacity(0.35), radius: 12, x: 0, y: 8)

                MiaraSpeechBubble(
                    text: FlowLocalization.app(
                        "Hi! I'll show you your first trend in just a week.",
                        "Cześć! Pierwszy trend pokażę Ci już za tydzień.",
                        "¡Hola! Te mostraré tu primera tendencia en una semana.",
                        "Hi! Deinen ersten Trend zeige ich dir schon in einer Woche.",
                        "Salut ! Je vous montrerai votre première tendance dans une semaine.",
                        "Oi! Vou te mostrar sua primeira tendência em uma semana."
                    )
                )
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var welcomeProofCard: some View {
        HStack(spacing: 0) {
            welcomeProofHalf(
                assetName: "onboarding-before",
                badge: FlowLocalization.app("Start", "Start", "Inicio", "Start", "Départ", "Início"),
                accent: false,
                alignment: .bottomLeading
            )
            welcomeProofHalf(
                assetName: "onboarding-after",
                badge: FlowLocalization.app("Week 12", "Tydzień 12", "Semana 12", "Woche 12", "Semaine 12", "Semana 12"),
                accent: true,
                alignment: .bottomTrailing
            )
        }
        .frame(height: 250)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.65))
                .frame(width: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .stroke(AppColorRoles.borderSubtle, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 12)
    }

    private func welcomeProofHalf(assetName: String, badge: String, accent: Bool, alignment: Alignment) -> some View {
        Image(assetName)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity)
            .frame(height: 250)
            .clipped()
            .overlay(alignment: alignment) {
                Text(badge)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(accent ? AppColorRoles.textOnAccent : Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(accent ? Color.appAccent : Color.black.opacity(0.62))
                    )
                    .padding(12)
            }
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
