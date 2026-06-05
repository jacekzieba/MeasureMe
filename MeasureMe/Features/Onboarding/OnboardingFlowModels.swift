import Foundation

enum OnboardingPriority: String, CaseIterable, Sendable {
    case loseWeight
    case buildMuscle
    case improveHealth
    case trackHealth

    static var onboardingOptions: [OnboardingPriority] {
        [.loseWeight, .buildMuscle, .improveHealth, .trackHealth]
    }

    var analyticsValue: String { rawValue }
}

enum ActivationTask: String, CaseIterable, Sendable {
    case firstMeasurement
    case chooseMetrics
    case setReminders
    case addPhoto
    case connectHealth
    case personalizeProfile
    case explorePremium

    static let initial: ActivationTask = .firstMeasurement
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
        case .trackHealth:
            return FlowLocalization.app("Track health", "Śledzić zdrowie", "Seguir salud", "Gesundheit verfolgen", "Suivre la santé", "Acompanhar saúde")
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
        case .trackHealth:
            return FlowLocalization.app(
                "Keep a simple baseline for long-term trends.",
                "Zbuduj prosty punkt startowy dla długoterminowych trendów.",
                "Crea una base simple para tendencias a largo plazo.",
                "Baue eine einfache Basis für langfristige Trends auf.",
                "Créez une base simple pour les tendances à long terme.",
                "Crie uma base simples para tendências de longo prazo."
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
        FlowLocalization.app("Import your starting point", "Zaimportuj punkt startowy", "Importa tu punto de partida", "Startpunkt importieren", "Importez votre point de départ", "Importe seu ponto inicial")
    }

    static var healthPromptBody: String {
        FlowLocalization.app(
            "MeasureMe can read selected measurements from Apple Health to create your baseline. Health access is optional and you can log manually instead.",
            "MeasureMe może odczytać wybrane pomiary z Apple Health, aby utworzyć punkt startowy. Dostęp do Zdrowia jest opcjonalny i możesz wpisywać dane ręcznie.",
            "MeasureMe puede leer medidas seleccionadas de Apple Health para crear tu base. El acceso a Salud es opcional y también puedes registrar manualmente.",
            "MeasureMe kann ausgewählte Messwerte aus Apple Health lesen, um deine Basis zu erstellen. Health-Zugriff ist optional und du kannst manuell eintragen.",
            "MeasureMe peut lire certaines mesures depuis Apple Health pour créer votre base. L'accès Santé est facultatif et vous pouvez saisir les données manuellement.",
            "O MeasureMe pode ler medições selecionadas do Apple Health para criar sua base. O acesso ao Health é opcional e você pode registrar manualmente."
        )
    }

    static var healthAllowCTA: String {
        FlowLocalization.app("Continue", "Dalej", "Continuar", "Weiter", "Continuer", "Continuar")
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
            return FlowLocalization.app("Confirm your starting measurements", "Potwierdź pomiary startowe", "Confirma tus medidas iniciales", "Startmessungen bestätigen", "Confirmez vos mesures de départ", "Confirme suas medições iniciais")
        case .chooseMetrics:
            return FlowLocalization.app("Choose what to track", "Wybierz, co śledzić", "Elige qué seguir", "Wähle, was du verfolgen willst", "Choisissez quoi suivre", "Escolha o que acompanhar")
        case .setReminders:
            return FlowLocalization.app("Set a weekly check-in reminder", "Ustaw tygodniowe przypomnienie", "Configura un recordatorio semanal", "Wöchentliche Erinnerung einrichten", "Définissez un rappel hebdomadaire", "Defina um lembrete semanal")
        case .addPhoto:
            return FlowLocalization.app("Add a progress photo", "Dodaj zdjęcie postępu", "Añade una foto de progreso", "Fortschrittsfoto hinzufügen", "Ajoutez une photo de progression", "Adicione uma foto de progresso")
        case .connectHealth:
            return FlowLocalization.app("Connect Apple Health", "Połącz z Apple Health", "Conecta Apple Health", "Mit Apple Health verbinden", "Connecter Apple Health", "Conectar Apple Health")
        case .personalizeProfile:
            return FlowLocalization.app("Personalize your profile", "Uzupełnij profil", "Personaliza tu perfil", "Profil ausfüllen", "Personnalisez votre profil", "Personalize seu perfil")
        case .explorePremium:
            return FlowLocalization.app("Explore Premium", "Sprawdź Premium", "Explora Premium", "Premium ansehen", "Découvrez Premium", "Explore o Premium")
        }
    }

    static func activationTaskBody(_ task: ActivationTask, metricName: String? = nil) -> String {
        switch task {
        case .firstMeasurement:
            return FlowLocalization.app(
                "Add or import your first Weight + Waist baseline.",
                "Dodaj lub zaimportuj pierwszą bazę Waga + Pas.",
                "Añade o importa tu primera base de Peso + Cintura.",
                "Füge deine erste Basis aus Gewicht + Taille hinzu oder importiere sie.",
                "Ajoutez ou importez votre première base Poids + Taille.",
                "Adicione ou importe sua primeira base de Peso + Cintura."
            )
        case .chooseMetrics:
            return FlowLocalization.app(
                "Customize the measurements that match your goal.",
                "Dostosuj pomiary do swojego celu.",
                "Personaliza las medidas que coinciden con tu objetivo.",
                "Passe die Messwerte an dein Ziel an.",
                "Personnalisez les mesures qui correspondent à votre objectif.",
                "Personalize as medições que combinam com seu objetivo."
            )
        case .setReminders:
            return FlowLocalization.app(
                "Build a consistent tracking habit.",
                "Zbuduj regularny nawyk śledzenia.",
                "Crea un hábito constante de seguimiento.",
                "Baue eine konstante Tracking-Gewohnheit auf.",
                "Créez une habitude de suivi régulière.",
                "Crie um hábito consistente de acompanhamento."
            )
        case .addPhoto:
            return FlowLocalization.app(
                "Optional, but useful for visual comparison.",
                "Opcjonalne, ale przydatne do porównań wizualnych.",
                "Opcional, pero útil para comparar visualmente.",
                "Optional, aber nützlich für visuelle Vergleiche.",
                "Facultatif, mais utile pour la comparaison visuelle.",
                "Opcional, mas útil para comparação visual."
            )
        case .connectHealth:
            return FlowLocalization.app(
                "Sync supported measurements automatically with Apple Health.",
                "Synchronizuj obsługiwane pomiary automatycznie z Apple Health.",
                "Sincroniza medidas compatibles automáticamente con Apple Health.",
                "Synchronisiere unterstützte Messwerte automatisch mit Apple Health.",
                "Synchronisez automatiquement les mesures compatibles avec Apple Health.",
                "Sincronize medições compatíveis automaticamente com Apple Health."
            )
        case .personalizeProfile:
            return FlowLocalization.app(
                "Add your height, age and gender so health indicators stay accurate.",
                "Dodaj wzrost, wiek i płeć, aby wskaźniki zdrowia były trafne.",
                "Añade tu altura, edad y género para que los indicadores sean precisos.",
                "Trage Größe, Alter und Geschlecht ein, damit die Indikatoren stimmen.",
                "Ajoutez votre taille, âge et genre pour des indicateurs précis.",
                "Adicione altura, idade e gênero para indicadores precisos."
            )
        case .explorePremium:
            return FlowLocalization.app(
                "See the advanced tools you can unlock when you need more depth.",
                "Zobacz zaawansowane narzędzia, które możesz odblokować, gdy potrzebujesz więcej.",
                "Mira las herramientas avanzadas que puedes desbloquear cuando necesites más detalle.",
                "Sieh dir die erweiterten Tools an, die du bei Bedarf freischalten kannst.",
                "Découvrez les outils avancés à débloquer si vous voulez aller plus loin.",
                "Veja as ferramentas avançadas que você pode desbloquear quando precisar de mais profundidade."
            )
        }
    }

    static func activationPrimaryCTA(_ task: ActivationTask) -> String {
        switch task {
        case .firstMeasurement:
            return FlowLocalization.app("Confirm baseline", "Potwierdź bazę", "Confirmar base", "Basis bestätigen", "Confirmer la base", "Confirmar base")
        case .addPhoto:
            return FlowLocalization.app("Add photo", "Dodaj zdjęcie", "Añadir foto", "Foto hinzufügen", "Ajouter une photo", "Adicionar foto")
        case .personalizeProfile:
            return FlowLocalization.app("Open profile", "Otwórz profil", "Abrir perfil", "Profil öffnen", "Ouvrir le profil", "Abrir perfil")
        case .connectHealth:
            return FlowLocalization.app("Connect", "Połącz", "Conectar", "Verbinden", "Connecter", "Conectar")
        case .chooseMetrics:
            return FlowLocalization.app("Review metrics", "Przejrzyj metryki", "Revisar métricas", "Messwerte prüfen", "Voir les mesures", "Revisar métricas")
        case .setReminders:
            return FlowLocalization.app("Set reminders", "Ustaw przypomnienia", "Configurar recordatorios", "Erinnerungen einrichten", "Définir des rappels", "Definir lembretes")
        case .explorePremium:
            return FlowLocalization.app("Explore Premium", "Sprawdź Premium", "Explorar Premium", "Premium ansehen", "Découvrir Premium", "Explorar Premium")
        }
    }

    static var activationSkipCTA: String {
        FlowLocalization.app("Skip", "Pomiń", "Omitir", "Überspringen", "Passer", "Pular")
    }

    static var activationDismissCTA: String {
        FlowLocalization.app("Hide for now", "Ukryj na teraz", "Ocultar por ahora", "Für jetzt ausblenden", "Masquer pour l'instant", "Ocultar por enquanto")
    }

    static var premiumTitle: String {
        FlowLocalization.app("Understand your progress faster", "Szybciej zrozum swój progres", "Entiende tu progreso más rápido", "Verstehe deinen Fortschritt schneller", "Comprenez vos progrès plus vite", "Entenda seu progresso mais rápido")
    }

    static var premiumBullets: [String] {
        [
            FlowLocalization.app("See whether weight change matches waist change", "Sprawdź, czy zmiana wagi pasuje do zmiany pasa", "Comprueba si el cambio de peso coincide con la cintura", "Sieh, ob Gewichts- und Taillenänderung zusammenpassen", "Voyez si le poids évolue comme la taille", "Veja se a mudança de peso combina com a cintura"),
            FlowLocalization.app("Compare photos side by side", "Porównuj zdjęcia obok siebie", "Compara fotos lado a lado", "Vergleiche Fotos nebeneinander", "Comparez les photos côte à côte", "Compare fotos lado a lado"),
            FlowLocalization.app("Get AI summaries from your measurements", "Otrzymuj podsumowania AI z pomiarów", "Obtén resúmenes de IA de tus medidas", "Erhalte KI-Zusammenfassungen aus deinen Messwerten", "Obtenez des résumés IA de vos mesures", "Receba resumos de IA das suas medições"),
            FlowLocalization.app("Export progress when you need it", "Eksportuj progres, gdy go potrzebujesz", "Exporta tu progreso cuando lo necesites", "Exportiere Fortschritt, wenn du ihn brauchst", "Exportez vos progrès si besoin", "Exporte o progresso quando precisar"),
            FlowLocalization.app("Keep long-term trends in one place", "Trzymaj długoterminowe trendy w jednym miejscu", "Mantén tendencias a largo plazo en un lugar", "Halte Langzeittrends an einem Ort", "Gardez les tendances long terme au même endroit", "Mantenha tendências de longo prazo em um lugar")
        ]
    }
}
