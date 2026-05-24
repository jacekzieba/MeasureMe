import SwiftUI
import UIKit

// MARK: - Metrics Step Data (preview cards and insight copy)

private extension OnboardingView {

    var metricsPreviewCards: [MetricsPreviewCardData] {
        switch resolvedPriority {
        case .loseWeight:
            return [
                MetricsPreviewCardData(
                    title: MetricKind.weight.title,
                    value: FlowLocalization.app("79.9 kg", "79,9 kg", "79,9 kg", "79,9 kg", "79,9 kg", "79,9 kg"),
                    delta: FlowLocalization.app("-2.3 kg", "-2,3 kg", "-2,3 kg", "-2,3 kg", "-2,3 kg", "-2,3 kg"),
                    tint: Color.appAccent,
                    backgroundTint: Color.appAccent,
                    points: [
                        CGPoint(x: 0.03, y: 0.30),
                        CGPoint(x: 0.24, y: 0.38),
                        CGPoint(x: 0.45, y: 0.49),
                        CGPoint(x: 0.66, y: 0.57),
                        CGPoint(x: 0.86, y: 0.68),
                        CGPoint(x: 0.97, y: 0.74)
                    ]
                ),
                MetricsPreviewCardData(
                    title: MetricKind.waist.title,
                    value: FlowLocalization.app("84.0 cm", "84,0 cm", "84,0 cm", "84,0 cm", "84,0 cm", "84,0 cm"),
                    delta: FlowLocalization.app("-4.1 cm", "-4,1 cm", "-4,1 cm", "-4,1 cm", "-4,1 cm", "-4,1 cm"),
                    tint: Color.cyan,
                    backgroundTint: Color.cyan.opacity(0.45),
                    points: [
                        CGPoint(x: 0.03, y: 0.34),
                        CGPoint(x: 0.22, y: 0.41),
                        CGPoint(x: 0.42, y: 0.50),
                        CGPoint(x: 0.63, y: 0.58),
                        CGPoint(x: 0.83, y: 0.67),
                        CGPoint(x: 0.97, y: 0.73)
                    ]
                )
            ]
        case .buildMuscle:
            return [
                MetricsPreviewCardData(
                    title: MetricKind.chest.title,
                    value: FlowLocalization.app("109.0 cm", "109,0 cm", "109,0 cm", "109,0 cm", "109,0 cm", "109,0 cm"),
                    delta: FlowLocalization.app("+3.2 cm", "+3,2 cm", "+3,2 cm", "+3,2 cm", "+3,2 cm", "+3,2 cm"),
                    tint: Color.appAccent,
                    backgroundTint: Color.appAccent,
                    points: [
                        CGPoint(x: 0.03, y: 0.68),
                        CGPoint(x: 0.24, y: 0.62),
                        CGPoint(x: 0.45, y: 0.54),
                        CGPoint(x: 0.66, y: 0.46),
                        CGPoint(x: 0.86, y: 0.37),
                        CGPoint(x: 0.97, y: 0.31)
                    ]
                ),
                MetricsPreviewCardData(
                    title: MetricKind.leftBicep.title,
                    value: FlowLocalization.app("40.1 cm", "40,1 cm", "40,1 cm", "40,1 cm", "40,1 cm", "40,1 cm"),
                    delta: FlowLocalization.app("+1.5 cm", "+1,5 cm", "+1,5 cm", "+1,5 cm", "+1,5 cm", "+1,5 cm"),
                    tint: Color.appTeal,
                    backgroundTint: Color.appTeal.opacity(0.4),
                    points: [
                        CGPoint(x: 0.03, y: 0.71),
                        CGPoint(x: 0.22, y: 0.67),
                        CGPoint(x: 0.42, y: 0.59),
                        CGPoint(x: 0.63, y: 0.48),
                        CGPoint(x: 0.83, y: 0.40),
                        CGPoint(x: 0.97, y: 0.33)
                    ]
                )
            ]
        case .improveHealth:
            return [
                MetricsPreviewCardData(
                    title: MetricKind.waist.title,
                    value: FlowLocalization.app("82.8 cm", "82,8 cm", "82,8 cm", "82,8 cm", "82,8 cm", "82,8 cm"),
                    delta: FlowLocalization.app("-2.6 cm", "-2,6 cm", "-2,6 cm", "-2,6 cm", "-2,6 cm", "-2,6 cm"),
                    tint: Color.cyan,
                    backgroundTint: Color.cyan.opacity(0.45),
                    points: [
                        CGPoint(x: 0.03, y: 0.35),
                        CGPoint(x: 0.22, y: 0.42),
                        CGPoint(x: 0.42, y: 0.51),
                        CGPoint(x: 0.63, y: 0.58),
                        CGPoint(x: 0.83, y: 0.66),
                        CGPoint(x: 0.97, y: 0.71)
                    ]
                ),
                MetricsPreviewCardData(
                    title: MetricKind.chest.title,
                    value: FlowLocalization.app("102.4 cm", "102,4 cm", "102,4 cm", "102,4 cm", "102,4 cm", "102,4 cm"),
                    delta: FlowLocalization.app("+1.1 cm", "+1,1 cm", "+1,1 cm", "+1,1 cm", "+1,1 cm", "+1,1 cm"),
                    tint: Color.appAccent,
                    backgroundTint: Color.appAccent,
                    points: [
                        CGPoint(x: 0.03, y: 0.66),
                        CGPoint(x: 0.24, y: 0.60),
                        CGPoint(x: 0.45, y: 0.55),
                        CGPoint(x: 0.66, y: 0.50),
                        CGPoint(x: 0.86, y: 0.43),
                        CGPoint(x: 0.97, y: 0.39)
                    ]
                )
            ]
        }
    }

    var metricsInsightCopy: MetricsInsightCopy {
        let personalizedIntro: String
        if let name = effectiveNameForGreeting {
            personalizedIntro = name
        } else {
            personalizedIntro = ""
        }

        switch resolvedPriority {
        case .loseWeight:
            let lineOne = personalizedIntro.isEmpty
                ? FlowLocalization.app(
                    "Weight is trending down and waist is tightening too.",
                    "Waga spada, a pas też się zmniejsza.",
                    "El peso baja y la cintura también se reduce.",
                    "Gewicht sinkt und die Taille wird ebenfalls kleiner.",
                    "Le poids baisse et la taille diminue aussi.",
                    "O peso está caindo e a cintura também."
                )
                : FlowLocalization.app(
                    "\(personalizedIntro), weight is trending down and waist is tightening too.",
                    "\(personalizedIntro), waga spada, a pas też się zmniejsza.",
                    "\(personalizedIntro), el peso baja y la cintura también se reduce.",
                    "\(personalizedIntro), Gewicht sinkt und die Taille wird ebenfalls kleiner.",
                    "\(personalizedIntro), le poids baisse et la taille diminue aussi.",
                    "\(personalizedIntro), o peso está caindo e a cintura também."
                )
            return MetricsInsightCopy(
                title: FlowLocalization.app("AI trend example", "Przykład trendu AI", "Ejemplo de tendencia IA", "KI-Trendbeispiel", "Exemple de tendance IA", "Exemplo de tendência de IA"),
                lineOne: lineOne,
                lineTwo: FlowLocalization.app(
                    "That is a much stronger fat-loss signal than scale weight on its own.",
                    "To dużo mocniejszy sygnał utraty tkanki tłuszczowej niż sama waga.",
                    "Eso es una señal de pérdida de grasa mucho más fuerte que el peso por sí solo.",
                    "Das ist ein deutlich stärkeres Fettverlust-Signal als das Gewicht allein.",
                    "C'est un signal de perte de graisse bien plus fort que le poids seul.",
                    "Esse é um sinal muito mais forte de perda de gordura do que o peso sozinho."
                ),
                tip: FlowLocalization.app(
                    "Keep protein high and keep your weekly movement consistent.",
                    "Trzymaj wysoko białko i utrzymuj regularny ruch w tygodniu.",
                    "Mantén alta la proteína y el movimiento semanal constante.",
                    "Halte die Proteinzufuhr hoch und deine Wochenbewegung konstant.",
                    "Gardez un apport élevé en protéines et un mouvement hebdomadaire régulier.",
                    "Mantenha proteína alta e movimento semanal consistente."
                )
            )
        case .buildMuscle:
            let lineOne = personalizedIntro.isEmpty
                ? FlowLocalization.app(
                    "Chest and left bicep are growing together.",
                    "Klatka i lewy biceps rosną razem.",
                    "Pecho y bíceps izquierdo están creciendo juntos.",
                    "Brust und linker Bizeps wachsen zusammen.",
                    "Le torse et le biceps gauche progressent ensemble.",
                    "Peito e bíceps esquerdo estão crescendo juntos."
                )
                : FlowLocalization.app(
                    "\(personalizedIntro), chest and left bicep are growing together.",
                    "\(personalizedIntro), klatka i lewy biceps rosną razem.",
                    "\(personalizedIntro), pecho y bíceps izquierdo están creciendo juntos.",
                    "\(personalizedIntro), Brust und linker Bizeps wachsen zusammen.",
                    "\(personalizedIntro), le torse et le biceps gauche progressent ensemble.",
                    "\(personalizedIntro), peito e bíceps esquerdo estão crescendo juntos."
                )
            return MetricsInsightCopy(
                title: FlowLocalization.app("AI trend example", "Przykład trendu AI", "Ejemplo de tendencia IA", "KI-Trendbeispiel", "Exemple de tendance IA", "Exemplo de tendência de IA"),
                lineOne: lineOne,
                lineTwo: FlowLocalization.app(
                    "This is the kind of signal that shows muscle gain before body weight explains it well.",
                    "To właśnie taki sygnał pokazuje budowę mięśni, zanim dobrze pokaże ją masa ciała.",
                    "Este es el tipo de señal que muestra músculo antes de que el peso lo explique.",
                    "Das ist die Art von Signal, die Muskelaufbau zeigt, bevor das Gewicht es gut erklärt.",
                    "C'est le type de signal qui montre le gain musculaire avant que le poids l'explique bien.",
                    "Esse é o tipo de sinal que mostra ganho muscular antes de o peso explicar bem."
                ),
                tip: FlowLocalization.app(
                    "Keep progressive overload steady and do not chase scale swings.",
                    "Utrzymuj progresywne przeciążenie i nie gon za wahaniami wagi.",
                    "Mantén la sobrecarga progresiva y no persigas las oscilaciones del peso.",
                    "Halte progressive Überlastung konstant und jage keinen Gewichtsschwankungen hinterher.",
                    "Gardez une surcharge progressive régulière et ne courez pas après la balance.",
                    "Mantenha a sobrecarga progressiva e não corra atrás das oscilações da balança."
                )
            )
        case .improveHealth:
            let lineOne = personalizedIntro.isEmpty
                ? FlowLocalization.app(
                    "Waist is tightening while chest stays full.",
                    "Pas się zmniejsza, a klatka zostaje pełna.",
                    "La cintura baja mientras el pecho se mantiene lleno.",
                    "Die Taille wird kleiner, während die Brust voll bleibt.",
                    "La taille diminue pendant que le torse reste plein.",
                    "A cintura está diminuindo enquanto o peito se mantém cheio."
                )
                : FlowLocalization.app(
                    "\(personalizedIntro), waist is tightening while chest stays full.",
                    "\(personalizedIntro), pas się zmniejsza, a klatka zostaje pełna.",
                    "\(personalizedIntro), la cintura baja mientras el pecho se mantiene lleno.",
                    "\(personalizedIntro), die Taille wird kleiner, während die Brust voll bleibt.",
                    "\(personalizedIntro), la taille diminue pendant que le torse reste plein.",
                    "\(personalizedIntro), a cintura está diminuindo enquanto o peito se mantém cheio."
                )
            return MetricsInsightCopy(
                title: FlowLocalization.app("AI trend example", "Przykład trendu AI", "Ejemplo de tendencia IA", "KI-Trendbeispiel", "Exemple de tendance IA", "Exemplo de tendência de IA"),
                lineOne: lineOne,
                lineTwo: FlowLocalization.app(
                    "That usually reads like recomposition, not random day-to-day noise.",
                    "To zwykle wygląda na rekompozycję, a nie losowy codzienny szum.",
                    "Eso suele parecer recomposición, no ruido diario aleatorio.",
                    "Das liest sich meist wie Recomposition, nicht wie tägliches Rauschen.",
                    "Cela ressemble généralement à une recomposition, pas à un bruit quotidien aléatoire.",
                    "Isso geralmente parece recomposição, não ruído aleatório do dia a dia."
                ),
                tip: FlowLocalization.app(
                    "Trust 2-4 week trends and keep your lifting routine boringly consistent.",
                    "Ufaj trendom z 2-4 tygodni i trzymaj nudno regularny trening siłowy.",
                    "Confía en las tendencias de 2-4 semanas y mantén tu rutina de fuerza muy constante.",
                    "Vertraue 2-4-Wochen-Trends und halte dein Krafttraining langweilig konstant.",
                    "Fiez-vous aux tendances sur 2 à 4 semaines et gardez votre routine de force très régulière.",
                    "Confie nas tendências de 2-4 semanas e mantenha sua rotina de treino consistentemente chata."
                )
            )
        }
    }
}
