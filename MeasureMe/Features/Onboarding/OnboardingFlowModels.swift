import Foundation

enum OnboardingPriority: String, CaseIterable, Sendable {
    case loseWeight
    case buildMuscle
    case improveHealth

    var analyticsValue: String { rawValue }
}

enum ActivationTask: String, CaseIterable, Sendable {
    case addMetric
    case addPhoto
    case chooseMetrics
    case premium
    case celebrate

    static let initial: ActivationTask = .addMetric
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
            return FlowLocalization.app("Improve health", "Poprawić zdrowie", "Mejorar la salud", "Gesundheit verbessern", "Améliorer la santé", "Melhorar a saúde")
        }
    }

    static func prioritySubtitle(_ priority: OnboardingPriority) -> String {
        switch priority {
        case .loseWeight:
            return FlowLocalization.app(
                "Focus on the measurements that reveal fat loss early.",
                "Skup się na metrykach, które szybko pokażą utratę tkanki tłuszczowej.",
                "Concéntrate en las métricas que muestran pronto la pérdida de grasa.",
                "Konzentriere dich auf Messwerte, die Fettverlust früh sichtbar machen.",
                "Concentrez-vous sur les mesures qui révèlent tôt la perte de graisse.",
                "Foque nas métricas que mostram cedo a perda de gordura."
            )
        case .buildMuscle:
            return FlowLocalization.app(
                "Track strength-oriented body changes, not just body weight.",
                "Śledź zmiany sylwetki związane z budową mięśni, a nie tylko wagę.",
                "Sigue cambios corporales ligados al músculo, no solo el peso.",
                "Verfolge muskelbezogene Körperveränderungen, nicht nur das Gewicht.",
                "Suivez les changements corporels liés au muscle, pas seulement le poids.",
                "Acompanhe mudanças corporais ligadas a músculos, não só o peso."
            )
        case .improveHealth:
            return FlowLocalization.app(
                "Stay close to the signals linked to metabolic and overall health.",
                "Trzymaj się sygnałów powiązanych ze zdrowiem metabolicznym i ogólnym.",
                "Mantente cerca de las señales ligadas a la salud metabólica y general.",
                "Bleib bei Signalen, die mit Stoffwechsel- und Gesamtgesundheit verbunden sind.",
                "Restez proche des signaux liés à la santé métabolique et globale.",
                "Fique perto dos sinais ligados à saúde metabólica e geral."
            )
        }
    }

    static func recommendedMetricTitles(for priority: OnboardingPriority) -> [String] {
        GoalMetricPack.recommendedKinds(for: priority).map(\.title)
    }

    static func introTitle(index: Int) -> String {
        switch index {
        case 0: return "MeasureMe"
        case 1: return "Metrics"
        case 2: return FlowLocalization.app("Photos that show the change", "Zdjęcia, które pokazują zmianę", "Fotos que muestran el cambio", "Fotos, die Veränderung sichtbar machen", "Des photos qui montrent le changement", "Fotos que mostram a mudança")
        case 3: return FlowLocalization.app("Health and Aesthetics", "Zdrowie i estetyka", "Salud y estética", "Gesundheit und Ästhetik", "Santé et esthétique", "Saúde e estética")
        default: return FlowLocalization.app("Private insights, on device", "Prywatne analizy, na urządzeniu", "Insights privados, en el dispositivo", "Private Einblicke, auf dem Gerät", "Insights privés, sur l'appareil", "Insights privados, no dispositivo")
        }
    }

    static func introSubtitle(index: Int) -> String {
        switch index {
        case 0:
            return FlowLocalization.system(
                motto,
                "Mierz to, co naprawdę ma znaczenie",
                "Mide lo que importa",
                "Miss, was wichtig ist",
                "Mesurez ce qui compte",
                "Meça o que importa"
            )
        case 1:
            return FlowLocalization.app(
                "Track the numbers that actually move your progress, not a wall of data.",
                "Śledź liczby, które naprawdę poruszają Twój progres, a nie ścianę danych.",
                "Sigue los números que realmente mueven tu progreso, no una pared de datos.",
                "Verfolge die Zahlen, die deinen Fortschritt wirklich bewegen, nicht eine Datenwand.",
                "Suivez les chiffres qui font réellement avancer votre progression, pas un mur de données.",
                "Acompanhe os números que realmente movem seu progresso, não uma parede de dados."
            )
        case 2:
            return FlowLocalization.app(
                "Compare progress over time with views that make subtle changes obvious.",
                "Porównuj postępy w czasie widokami, które wyciągają subtelne zmiany na pierwszy plan.",
                "Compara el progreso con vistas que hacen evidentes los cambios sutiles.",
                "Vergleiche Fortschritte über die Zeit mit Ansichten, die subtile Veränderungen sichtbar machen.",
                "Comparez les progrès dans le temps avec des vues qui rendent les changements subtils évidents.",
                "Compare o progresso ao longo do tempo com visões que deixam mudanças sutis óbvias."
            )
        case 3:
            return FlowLocalization.app(
                "Turn raw measurements into signals for health risk, body composition, and physique balance.",
                "Zamień surowe pomiary w sygnały o ryzyku zdrowotnym, kompozycji ciała i proporcjach sylwetki.",
                "Convierte medidas en señales sobre riesgo de salud, composición corporal y equilibrio físico.",
                "Verwandle rohe Messwerte in Signale für Gesundheitsrisiko, Körperzusammensetzung und Körperbalance.",
                "Transformez des mesures brutes en signaux pour le risque santé, la composition corporelle et l'équilibre physique.",
                "Transforme medidas brutas em sinais sobre risco à saúde, composição corporal e equilíbrio físico."
            )
        default:
            return FlowLocalization.app(
                "Apple Intelligence helps summarize your trends on device. Your photos and measurements stay yours.",
                "Apple Intelligence pomaga podsumować trendy na urządzeniu. Twoje zdjęcia i pomiary pozostają Twoje.",
                "Apple Intelligence ayuda a resumir tus tendencias en el dispositivo. Tus fotos y medidas siguen siendo tuyas.",
                "Apple Intelligence fasst deine Trends auf dem Gerät zusammen. Deine Fotos und Messwerte bleiben deine.",
                "Apple Intelligence aide à résumer vos tendances sur l'appareil. Vos photos et mesures restent les vôtres.",
                "A Apple Intelligence ajuda a resumir suas tendências no dispositivo. Suas fotos e medições continuam sendo suas."
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
            "What's your main priority right now?",
            "Jaki jest teraz Twój główny priorytet?",
            "¿Cuál es tu prioridad principal ahora mismo?",
            "Was ist gerade deine wichtigste Priorität?",
            "Quelle est votre priorité principale en ce moment ?",
            "Qual é sua principal prioridade agora?"
        )
    }

    static var personalizingTitle: String {
        FlowLocalization.app("Personalizing your experience", "Personalizujemy Twoje doświadczenie", "Personalizando tu experiencia", "Wir personalisieren dein Erlebnis", "Personnalisation de votre expérience", "Personalizando sua experiência")
    }

    static var healthPromptTitle: String {
        FlowLocalization.app("Recommended metrics for you", "Polecane metryki dla Ciebie", "Métricas recomendadas para ti", "Empfohlene Messwerte für dich", "Mesures recommandées pour vous", "Métricas recomendadas para você")
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
        FlowLocalization.app("Allow access to Health", "Zezwól na dostęp do Health", "Permitir acceso a Salud", "Zugriff auf Health erlauben", "Autoriser l'accès à Santé", "Permitir acesso ao Health")
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
        FlowLocalization.app("Learn the core flows", "Poznaj najważniejsze ścieżki", "Aprende los flujos clave", "Lerne die Kernabläufe kennen", "Découvrez les parcours clés", "Conheça os fluxos principais")
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
        case .addMetric:
            return FlowLocalization.app("Add one metric", "Dodaj jedną metrykę", "Añade una métrica", "Füge eine Messung hinzu", "Ajoutez une mesure", "Adicione uma métrica")
        case .addPhoto:
            return FlowLocalization.app("Add your first photo", "Dodaj pierwsze zdjęcie", "Añade tu primera foto", "Füge dein erstes Foto hinzu", "Ajoutez votre première photo", "Adicione sua primeira foto")
        case .chooseMetrics:
            return FlowLocalization.app("Choose what to track", "Wybierz, co śledzić", "Elige qué seguir", "Wähle, was du verfolgen willst", "Choisissez quoi suivre", "Escolha o que acompanhar")
        case .premium:
            return FlowLocalization.app("See what Premium unlocks", "Zobacz, co odblokowuje Premium", "Mira lo que desbloquea Premium", "Sieh, was Premium freischaltet", "Voyez ce que Premium débloque", "Veja o que o Premium desbloqueia")
        case .celebrate:
            return FlowLocalization.app("You're ready to go", "Jesteś gotowy do startu", "Ya estás listo", "Du bist startklar", "Vous êtes prêt", "Você está pronto")
        }
    }

    static func activationTaskBody(_ task: ActivationTask, metricName: String? = nil) -> String {
        switch task {
        case .addMetric:
            let fallback = FlowLocalization.app("your recommended metric", "polecaną metrykę", "tu métrica recomendada", "deinen empfohlenen Messwert", "votre mesure recommandée", "sua métrica recomendada")
            let resolved = metricName ?? fallback
            return FlowLocalization.app(
                "Log \(resolved) yourself once so the app can anchor your trend around a real check-in.",
                "Zapisz samodzielnie \(resolved) jeden raz, aby aplikacja mogła oprzeć trend o realny check-in.",
                "Registra \(resolved) una vez para que la app ancle tu tendencia en un check-in real.",
                "Trage \(resolved) einmal selbst ein, damit die App deinen Trend auf einen echten Check-in stützen kann.",
                "Enregistrez \(resolved) une fois vous-même pour ancrer la tendance sur un vrai check-in.",
                "Registre \(resolved) uma vez para que o app ancore sua tendência em um check-in real."
            )
        case .addPhoto:
            return FlowLocalization.app(
                "A single progress photo makes later comparisons dramatically more useful.",
                "Jedno zdjęcie progresu sprawia, że późniejsze porównania stają się dużo bardziej użyteczne.",
                "Una sola foto de progreso vuelve mucho más útil la comparación posterior.",
                "Ein einziges Fortschrittsfoto macht spätere Vergleiche deutlich nützlicher.",
                "Une seule photo de progression rend les comparaisons futures bien plus utiles.",
                "Uma única foto de progresso torna comparações futuras muito mais úteis."
            )
        case .chooseMetrics:
            return FlowLocalization.app(
                "Pick the metrics that deserve space on your home and quick-add surfaces.",
                "Wybierz metryki, które mają dostać miejsce na home i w szybkim dodawaniu.",
                "Elige las métricas que merecen espacio en inicio y en el acceso rápido.",
                "Wähle die Messwerte, die Platz auf Home und im Schnellzugriff bekommen sollen.",
                "Choisissez les mesures qui méritent une place sur l'accueil et dans l'ajout rapide.",
                "Escolha as métricas que merecem espaço na home e no atalho de adição."
            )
        case .premium:
            return FlowLocalization.app(
                "Compare photos side by side, unlock deeper insights, and keep your progress story richer.",
                "Porównuj zdjęcia obok siebie, odblokuj głębsze analizy i zbuduj pełniejszą historię progresu.",
                "Compara fotos lado a lado, desbloquea insights más profundos y enriquece tu historia de progreso.",
                "Vergleiche Fotos nebeneinander, schalte tiefere Einblicke frei und erzähle deine Fortschrittsgeschichte besser.",
                "Comparez les photos côte à côte, débloquez des insights plus profonds et enrichissez votre histoire de progression.",
                "Compare fotos lado a lado, desbloqueie insights mais profundos e enriqueça sua história de progresso."
            )
        case .celebrate:
            return FlowLocalization.app(
                "You have everything needed to start building momentum inside MeasureMe.",
                "Masz już wszystko, czego potrzeba, aby zacząć budować rozpęd w MeasureMe.",
                "Ya tienes todo lo necesario para empezar a ganar impulso en MeasureMe.",
                "Du hast jetzt alles, was du brauchst, um in MeasureMe Momentum aufzubauen.",
                "Vous avez maintenant tout ce qu'il faut pour lancer votre dynamique dans MeasureMe.",
                "Você já tem tudo para começar a ganhar ritmo no MeasureMe."
            )
        }
    }

    static func activationPrimaryCTA(_ task: ActivationTask) -> String {
        switch task {
        case .addMetric:
            return FlowLocalization.app("Add metric", "Dodaj metrykę", "Añadir métrica", "Messung hinzufügen", "Ajouter une mesure", "Adicionar métrica")
        case .addPhoto:
            return FlowLocalization.app("Add photo", "Dodaj zdjęcie", "Añadir foto", "Foto hinzufügen", "Ajouter une photo", "Adicionar foto")
        case .chooseMetrics:
            return FlowLocalization.app("Review metrics", "Przejrzyj metryki", "Revisar métricas", "Messwerte prüfen", "Voir les mesures", "Revisar métricas")
        case .premium:
            return FlowLocalization.app("See Premium", "Zobacz Premium", "Ver Premium", "Premium ansehen", "Voir Premium", "Ver Premium")
        case .celebrate:
            return FlowLocalization.app("Go to dashboard", "Przejdź do dashboardu", "Ir al panel", "Zum Dashboard", "Aller au tableau de bord", "Ir para o dashboard")
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
