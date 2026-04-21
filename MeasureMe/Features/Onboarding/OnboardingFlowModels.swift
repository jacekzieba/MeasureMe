import Foundation

enum OnboardingPriority: String, CaseIterable, Sendable {
    case loseWeight
    case buildMuscle
    case improveHealth

    var analyticsValue: String { rawValue }
}

enum ActivationTask: String, CaseIterable, Sendable {
    case firstMeasurement
    case addPhoto
    case chooseMetrics
    case setGoal

    static let initial: ActivationTask = .addPhoto
}

enum FlowLocalization {
    static func app(
        _ en: String,
        _ pl: String,
        _ es: String,
        _ de: String,
        _ fr: String,
        _ ptBR: String
    ) -> String {
        switch AppLocalization.currentLanguage {
        case .system:
            return system(en, pl, es, de, fr, ptBR)
        case .en:
            return en
        case .pl:
            return pl
        case .es:
            return es
        case .de:
            return de
        case .fr:
            return fr
        case .ptBR:
            return ptBR
        }
    }

    static func system(
        _ en: String,
        _ pl: String,
        _ es: String,
        _ de: String,
        _ fr: String,
        _ ptBR: String
    ) -> String {
        switch AppLanguage.resolvedSystemLanguage {
        case .system, .en:
            return en
        case .pl:
            return pl
        case .es:
            return es
        case .de:
            return de
        case .fr:
            return fr
        case .ptBR:
            return ptBR
        }
    }
}

enum OnboardingCopy {
    static let motto = "Measure what matters"

    static func priorityTitle(_ priority: OnboardingPriority) -> String {
        switch priority {
        case .loseWeight:
            return FlowLocalization.app("Lose weight", "Schudnąć", "Perder peso", "Abnehmen", "Perdre du poids", "Perder peso")
        case .buildMuscle:
            return FlowLocalization.app("Build muscle", "Budować mięśnie", "Ganar músculo", "Muskeln aufbauen", "Prendre du muscle", "Ganhar massa muscular")
        case .improveHealth:
            return FlowLocalization.app("Recomposition", "Rekompozycja", "Recomposición", "Rekomposition", "Recomposition", "Recomposição")
        }
    }

    static func prioritySubtitle(_ priority: OnboardingPriority) -> String {
        switch priority {
        case .loseWeight:
            return FlowLocalization.app(
                "Start with weight and waist so fat loss becomes easier to read.",
                "Zacznij od wagi i pasa, aby łatwiej odczytywać utratę tkanki tłuszczowej.",
                "Empieza con peso y cintura para leer mejor la pérdida de grasa.",
                "Starte mit Gewicht und Taille, damit Fettverlust leichter lesbar wird.",
                "Commencez par le poids et la taille pour mieux lire la perte de graisse.",
                "Comece com peso e cintura para enxergar melhor a perda de gordura."
            )
        case .buildMuscle:
            return FlowLocalization.app(
                "Focus on chest and arm growth instead of obsessing over scale weight.",
                "Skup się na wzroście klatki i ramion zamiast obsesyjnie patrzeć na wagę.",
                "Enfócate en el crecimiento de pecho y brazo en lugar de obsesionarte con la báscula.",
                "Konzentriere dich auf Brust- und Armzuwachs statt auf die Waage.",
                "Concentrez-vous sur la progression du torse et des bras plutôt que sur la balance.",
                "Foque no crescimento do peito e do braço em vez de se prender à balança."
            )
        case .improveHealth:
            return FlowLocalization.app(
                "Use waist and chest together to spot recomposition without overreacting to daily noise.",
                "Używaj razem pasa i klatki, aby wychwycić rekompozycję bez reagowania na codzienny szum.",
                "Usa cintura y pecho juntos para detectar recomposición sin reaccionar al ruido diario.",
                "Nutze Taille und Brust zusammen, um Recomposition ohne täglichen Lärm zu erkennen.",
                "Utilisez la taille et le torse ensemble pour repérer la recomposition sans réagir au bruit quotidien.",
                "Use cintura e peito juntos para notar recomposição sem reagir ao ruído diário."
            )
        }
    }

    static func recommendedMetricTitles(for priority: OnboardingPriority) -> [String] {
        GoalMetricPack.recommendedKinds(for: priority).map(\.title)
    }

    static func introTitle(index: Int) -> String {
        switch index {
        case 0: return "Metrics"
        case 1: return FlowLocalization.app("Photos that show the change", "Zdjęcia, które pokazują zmianę", "Fotos que muestran el cambio", "Fotos, die Veränderung sichtbar machen", "Des photos qui montrent le changement", "Fotos que mostram a mudança")
        default: return FlowLocalization.app("Private insights, on device", "Prywatne analizy, na urządzeniu", "Insights privados, en el dispositivo", "Private Einblicke, auf dem Gerät", "Insights privés, sur l'appareil", "Insights privados, no dispositivo")
        }
    }

    static func introSubtitle(index: Int) -> String {
        switch index {
        case 0:
            return FlowLocalization.app(
                "Track the numbers that actually move your progress, not a wall of data.",
                "Śledź liczby, które naprawdę poruszają Twój progres, a nie ścianę danych.",
                "Sigue los números que realmente mueven tu progreso, no una pared de datos.",
                "Verfolge die Zahlen, die deinen Fortschritt wirklich bewegen, nicht eine Datenwand.",
                "Suivez les chiffres qui font réellement avancer votre progression, pas un mur de données.",
                "Acompanhe os números que realmente movem seu progresso, não uma parede de dados."
            )
        case 1:
            return FlowLocalization.app(
                "Compare progress over time with views that make subtle changes obvious.",
                "Porównuj postępy w czasie widokami, które wyciągają subtelne zmiany na pierwszy plan.",
                "Compara el progreso con vistas que hacen evidentes los cambios sutiles.",
                "Vergleiche Fortschritte über die Zeit mit Ansichten, die subtile Veränderungen sichtbar machen.",
                "Comparez les progrès dans le temps avec des vues qui rendent les changements subtils évidents.",
                "Compare o progresso ao longo do tempo com visões que deixam mudanças sutis óbvias."
            )
        default:
            return FlowLocalization.app(
                "Apple Intelligence helps summarize your trends on device. Your photos and measurements never leave your device.",
                "Apple Intelligence pomaga podsumować trendy na urządzeniu. Twoje zdjęcia i pomiary nigdy nie opuszczają urządzenia.",
                "Apple Intelligence ayuda a resumir tus tendencias en el dispositivo. Tus fotos y medidas nunca salen de tu dispositivo.",
                "Apple Intelligence fasst deine Trends auf dem Gerät zusammen. Deine Fotos und Messwerte verlassen dein Gerät nie.",
                "Apple Intelligence aide à résumer vos tendances sur l'appareil. Vos photos et mesures ne quittent jamais votre appareil.",
                "A Apple Intelligence ajuda a resumir suas tendências no dispositivo. Suas fotos e medições nunca saem do seu dispositivo."
            )
        }
    }

    static var namePrompt: String {
        FlowLocalization.app(
            "What's your first name?",
            "Jak masz na imię?",
            "¿Cuál es tu nombre?",
            "Wie ist dein Vorname?",
            "Quel est votre prénom ?",
            "Qual é o seu primeiro nome?"
        )
    }

    static func greeting(name: String?) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return FlowLocalization.app("Nice to meet you.", "Miło Cię poznać.", "Encantado de conocerte.", "Schön, dich kennenzulernen.", "Ravi de vous rencontrer.", "Prazer em conhecer você.")
        }
        return FlowLocalization.app(
            "Nice to meet you, \(trimmed).",
            "Miło Cię poznać, \(trimmed).",
            "Encantado de conocerte, \(trimmed).",
            "Schön, dich kennenzulernen, \(trimmed).",
            "Ravi de vous rencontrer, \(trimmed).",
            "Prazer em conhecer você, \(trimmed)."
        )
    }

    static var greetingBody: String {
        FlowLocalization.app(
            "MeasureMe helps you stay consistent, see progress earlier, and focus on what matters most to you.",
            "MeasureMe pomaga utrzymać regularność, szybciej zauważać progres i skupić się na tym, co najważniejsze dla Ciebie.",
            "MeasureMe te ayuda a ser constante, ver progreso antes y centrarte en lo que más importa para ti.",
            "MeasureMe hilft dir, konsequent zu bleiben, Fortschritte früher zu sehen und dich auf das Wichtigste zu konzentrieren.",
            "MeasureMe vous aide à rester constant, à voir vos progrès plus tôt et à vous concentrer sur l'essentiel.",
            "O MeasureMe ajuda você a manter consistência, perceber progresso mais cedo e focar no que mais importa."
        )
    }

    static var priorityPrompt: String {
        FlowLocalization.app(
            "What are your main priorities right now?",
            "Jakie są teraz Twoje główne priorytety?",
            "¿Cuáles son tus prioridades principales ahora mismo?",
            "Was sind gerade deine wichtigsten Prioritäten?",
            "Quelles sont vos priorités principales en ce moment ?",
            "Quais são suas principais prioridades agora?"
        )
    }

    static func priorityPrompt(name: String?) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return priorityPrompt }
        return FlowLocalization.app(
            "Nice to meet you, \(trimmed). What are your priorities right now?",
            "Miło Cię poznać, \(trimmed). Jakie są teraz Twoje priorytety?",
            "Encantado de conocerte, \(trimmed). ¿Cuáles son tus prioridades ahora?",
            "Schön, dich kennenzulernen, \(trimmed). Was sind gerade deine Prioritäten?",
            "Ravi de vous rencontrer, \(trimmed). Quelles sont vos priorités en ce moment ?",
            "Prazer em conhecer você, \(trimmed). Quais são suas prioridades agora?"
        )
    }

    static var priorityHelper: String {
        FlowLocalization.app(
            "Choose one to continue.",
            "Wybierz jeden cel, aby kontynuować.",
            "Elige uno para continuar.",
            "Wähle ein Ziel, um fortzufahren.",
            "Choisissez-en un pour continuer.",
            "Escolha um para continuar."
        )
    }

    static var personalizingTitle: String {
        FlowLocalization.app("Personalizing your experience", "Personalizujemy Twoje doświadczenie", "Personalizando tu experiencia", "Wir personalisieren dein Erlebnis", "Personnalisation de votre expérience", "Personalizando sua experiência")
    }

    static var healthPromptTitle: String {
        FlowLocalization.app("Import from Apple Health?", "Zaimportować z Apple Health?", "¿Importar desde Apple Health?", "Aus Apple Health importieren?", "Importer depuis Apple Health ?", "Importar do Apple Health?")
    }

    static var healthPromptBody: String {
        FlowLocalization.app(
            "Connect Apple Health to import history and keep your baseline up to date automatically.",
            "Połącz Apple Health, aby zaimportować historię i automatycznie aktualizować punkt startowy.",
            "Conecta Apple Health para importar historial y mantener tu base al día automáticamente.",
            "Verbinde Apple Health, um Verlauf zu importieren und deine Basis automatisch aktuell zu halten.",
            "Connectez Apple Health pour importer l'historique et garder votre base à jour automatiquement.",
            "Conecte o Apple Health para importar histórico e manter sua base atualizada automaticamente."
        )
    }

    static var healthAllowCTA: String {
        FlowLocalization.app("Import history", "Importuj historię", "Importar historial", "Verlauf importieren", "Importer l'historique", "Importar histórico")
    }

    static var healthSkipCTA: String {
        FlowLocalization.app("Not now", "Nie teraz", "Ahora no", "Nicht jetzt", "Pas maintenant", "Agora não")
    }

    static var notificationsTitle: String {
        FlowLocalization.app("Keep the habit alive", "Podtrzymaj nawyk", "Mantén vivo el hábito", "Halte die Gewohnheit am Leben", "Gardez l'habitude vivante", "Mantenha o hábito vivo")
    }

    static var notificationsBody: String {
        FlowLocalization.app(
            "A small reminder keeps the streak alive.",
            "Małe przypomnienie pomaga utrzymać serię.",
            "Un pequeño recordatorio mantiene viva la racha.",
            "Eine kleine Erinnerung hält die Serie am Leben.",
            "Un petit rappel entretient la régularité.",
            "Um pequeno lembrete mantém a sequência viva."
        )
    }

    static var notificationsCTA: String {
        FlowLocalization.app("Enable notifications", "Włącz powiadomienia", "Activar notificaciones", "Benachrichtigungen aktivieren", "Activer les notifications", "Ativar notificações")
    }

    static var completionTitle: String {
        FlowLocalization.app("You're all set.", "Wszystko gotowe.", "Todo listo.", "Alles ist bereit.", "Tout est prêt.", "Tudo pronto.")
    }

    static var completionBody: String {
        FlowLocalization.app(
            "Your dashboard is ready. Start with one action and let the habit build from there.",
            "Twój dashboard jest gotowy. Zacznij od jednej akcji i buduj nawyk dalej.",
            "Tu panel está listo. Empieza con una acción y deja que el hábito crezca.",
            "Dein Dashboard ist bereit. Starte mit einer Aktion und lass daraus eine Gewohnheit werden.",
            "Votre tableau de bord est prêt. Commencez par une action et laissez l'habitude se construire.",
            "Seu dashboard está pronto. Comece com uma ação e deixe o hábito crescer a partir daí."
        )
    }

    static var activationEyebrow: String {
        FlowLocalization.app("Start here", "Zacznij tutaj", "Empieza aquí", "Hier starten", "Commencez ici", "Comece aqui")
    }

    static var activationTitle: String {
        FlowLocalization.app("Make it yours", "Dostosuj pod siebie", "Hazlo tuyo", "Mach es zu deinem", "Personnalisez-le", "Deixe com a sua cara")
    }

    static func activationSubtitle(step: Int, total: Int) -> String {
        FlowLocalization.app(
            "Step \(step) of \(total)",
            "Krok \(step) z \(total)",
            "Paso \(step) de \(total)",
            "Schritt \(step) von \(total)",
            "Étape \(step) sur \(total)",
            "Etapa \(step) de \(total)"
        )
    }

    static func activationTaskTitle(_ task: ActivationTask) -> String {
        switch task {
        case .firstMeasurement:
            return FlowLocalization.app("Add your first measurement", "Dodaj pierwszy pomiar", "Añade tu primera medida", "Füge deine erste Messung hinzu", "Ajoutez votre première mesure", "Adicione sua primeira medição")
        case .addPhoto:
            return FlowLocalization.app("Add your first photo", "Dodaj pierwsze zdjęcie", "Añade tu primera foto", "Füge dein erstes Foto hinzu", "Ajoutez votre première photo", "Adicione sua primeira foto")
        case .chooseMetrics:
            return FlowLocalization.app("Choose what to track", "Wybierz, co śledzić", "Elige qué seguir", "Wähle, was du verfolgen willst", "Choisissez quoi suivre", "Escolha o que acompanhar")
        case .setGoal:
            return FlowLocalization.app("Set your first goal", "Ustaw pierwszy cel", "Define tu primer objetivo", "Setze dein erstes Ziel", "Définissez votre premier objectif", "Defina sua primeira meta")
        }
    }

    static func activationTaskBody(_ task: ActivationTask, metricName: String? = nil) -> String {
        switch task {
        case .firstMeasurement:
            return FlowLocalization.app(
                "Log one measurement manually to create your starting point.",
                "Wpisz jeden pomiar ręcznie, aby utworzyć punkt startowy.",
                "Registra una medida manualmente para crear tu punto de partida.",
                "Trage eine Messung manuell ein, um deinen Startpunkt zu setzen.",
                "Enregistrez une mesure manuellement pour créer votre point de départ.",
                "Registre uma medição manualmente para criar seu ponto inicial."
            )
        case .addPhoto:
            return FlowLocalization.app(
                "Add one photo to make this starting point visual.",
                "Dodaj jedno zdjęcie, aby punkt startowy był widoczny.",
                "Añade una foto para hacer visual este punto de partida.",
                "Füge ein Foto hinzu, damit dein Startpunkt sichtbar wird.",
                "Ajoutez une photo pour rendre ce point de départ visuel.",
                "Adicione uma foto para deixar esse ponto inicial visual."
            )
        case .chooseMetrics:
            return FlowLocalization.app(
                "Pin the metrics you want on Home and Quick Add.",
                "Przypnij metryki, które chcesz widzieć na Home i w szybkim dodawaniu.",
                "Fija las métricas que quieres en Inicio y Añadir rápido.",
                "Pinne die Messwerte, die du auf Home und in Quick Add sehen willst.",
                "Épinglez les mesures à afficher sur l'accueil et l'ajout rapide.",
                "Fixe as métricas que você quer na Home e no atalho de adição."
            )
        case .setGoal:
            return FlowLocalization.app(
                "Give one tracked measurement a target to work toward.",
                "Nadaj jednej śledzonej metryce cel do osiągnięcia.",
                "Dale a una métrica un objetivo hacia el que avanzar.",
                "Gib einem Messwert ein Ziel, auf das du hinarbeitest.",
                "Donnez un objectif à une mesure suivie.",
                "Dê uma meta para uma métrica acompanhada."
            )
        }
    }

    static func activationPrimaryCTA(_ task: ActivationTask) -> String {
        switch task {
        case .firstMeasurement:
            return FlowLocalization.app("Add measurement", "Dodaj pomiar", "Añadir medida", "Messung hinzufügen", "Ajouter une mesure", "Adicionar medição")
        case .addPhoto:
            return FlowLocalization.app("Add photo", "Dodaj zdjęcie", "Añadir foto", "Foto hinzufügen", "Ajouter une photo", "Adicionar foto")
        case .chooseMetrics:
            return FlowLocalization.app("Review metrics", "Przejrzyj metryki", "Revisar métricas", "Messwerte prüfen", "Voir les mesures", "Revisar métricas")
        case .setGoal:
            return FlowLocalization.app("Set goal", "Ustaw cel", "Definir objetivo", "Ziel setzen", "Définir un objectif", "Definir meta")
        }
    }

    static var activationSkipCTA: String {
        FlowLocalization.app("Skip", "Pomiń", "Omitir", "Überspringen", "Passer", "Pular")
    }

    static var activationDismissCTA: String {
        FlowLocalization.app("Hide for now", "Ukryj na teraz", "Ocultar por ahora", "Für jetzt ausblenden", "Masquer pour l'instant", "Ocultar por enquanto")
    }

    static var premiumTitle: String {
        FlowLocalization.app("Go deeper when you're ready", "Wejdź głębiej, kiedy będziesz gotowy", "Ve más allá cuando quieras", "Geh tiefer, wenn du bereit bist", "Allez plus loin quand vous serez prêt", "Vá mais fundo quando estiver pronto")
    }

    static var premiumBullets: [String] {
        [
            FlowLocalization.app("Photo comparison modes", "Tryby porównywania zdjęć", "Modos de comparación de fotos", "Fotovergleichsmodi", "Modes de comparaison photo", "Modos de comparação de fotos"),
            FlowLocalization.app("AI summaries and richer trend context", "Analizy AI i bogatszy kontekst trendów", "Resúmenes de IA y contexto de tendencias", "KI-Zusammenfassungen und reicherer Trendkontext", "Résumés IA et contexte de tendance enrichi", "Resumos com IA e contexto de tendências"),
            FlowLocalization.app("Health and physique indicators in one place", "Wskaźniki zdrowia i sylwetki w jednym miejscu", "Indicadores de salud y físico en un solo lugar", "Gesundheits- und Körperindikatoren an einem Ort", "Indicateurs santé et silhouette au même endroit", "Indicadores de saúde e físico em um só lugar")
        ]
    }
}
