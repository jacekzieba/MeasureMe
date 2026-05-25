import SwiftUI
import SwiftData

// MARK: - Sheet Presentation

private extension HomeView {

    func sheetPresentedHomeRoot<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $showQuickAddSheet) {
                quickAddSheet
            }
            .sheet(isPresented: $showActivationAddPhotoSheet) {
                NavigationStack {
                    AddPhotoView(telemetrySource: .activation, onSaved: {
                        completeActivationTask(.addPhoto)
                    })
                    .environmentObject(metricsStore)
                }
            }
            .sheet(isPresented: $showActivationMetricsSheet) {
                ActivationMetricSelectionSheet(
                    recommendedKinds: activationRecommendedKinds,
                    metricsStore: metricsStore
                ) {
                    completeActivationTask(.chooseMetrics)
                }
            }
            .sheet(isPresented: $showHomeSettingsSheet) {
                NavigationStack {
                    HomeSettingsDetailView()
                }
            }
            .sheet(item: $selectedPhotoForFullScreen) { photo in
                PhotoDetailView(photo: photo)
            }
            .sheet(isPresented: $showHomeCompareChooser) {
                HomeCompareChooserOnDemandSheet(
                    initialOlderPhoto: secondLatestSavedPhoto,
                    initialNewerPhoto: latestSavedPhoto
                ) { olderPhoto, newerPhoto in
                    selectedHomeComparePair = HomeComparePair(olderPhoto: olderPhoto, newerPhoto: newerPhoto)
                }
                .presentationBackground(AppColorRoles.surfaceCanvas)
            }
            .sheet(item: $selectedHomeComparePair) { pair in
                ComparePhotosView(olderPhoto: pair.olderPhoto, newerPhoto: pair.newerPhoto)
            }
            .sheet(isPresented: $showStreakDetail) {
                StreakDetailView(streakManager: streakManager)
            }
            .sheet(isPresented: $showGoalStatusLegendSheet) {
                GoalStatusLegendSheet(currentStatus: goalStatus, currentStatusColor: goalStatusColor)
                    .presentationDetents([.fraction(0.42), .medium])
                    .presentationDragIndicator(.visible)
            }
            .alert(
                AppLocalization.string("Open iOS Settings now?"),
                isPresented: $shouldPromptToOpenHealthSettings
            ) {
                Button(AppLocalization.string("Open iOS Settings")) {
                    openAppSettings()
                }
                Button(AppLocalization.string("Not now"), role: .cancel) {}
            } message: {
                Text(AppLocalization.string("To enable Apple Health sync, go to iOS Settings → MeasureMe → Health."))
            }
            .alert(
                FlowLocalization.app(
                    "Want a nudge to log again tomorrow?",
                    "Chcesz przypomnienie, żeby jutro znów coś zapisać?",
                    "¿Quieres un recordatorio para registrar de nuevo mañana?",
                    "Möchtest du morgen an den nächsten Eintrag erinnert werden?",
                    "Voulez-vous un rappel pour enregistrer à nouveau demain ?",
                    "Quer um lembrete para registrar de novo amanhã?"
                ),
                isPresented: $showActivationReminderPrompt
            ) {
                Button(FlowLocalization.app("Not now", "Nie teraz", "Ahora no", "Nicht jetzt", "Pas maintenant", "Agora não"), role: .cancel) {
                    declineActivationReminderPrompt()
                }
                .accessibilityIdentifier("home.activation.reminder.skip")

                Button(FlowLocalization.app("Remind me tomorrow", "Przypomnij mi jutro", "Recordarme mañana", "Morgen erinnern", "Me le rappeler demain", "Lembrar amanhã")) {
                    acceptActivationReminderPrompt()
                }
                .accessibilityIdentifier("home.activation.reminder.accept")
            } message: {
                Text(FlowLocalization.app(
                    "You just logged your first measurement. A timely reminder can help make the second one easier.",
                    "Właśnie zapisano pierwszy pomiar. Dobre przypomnienie może ułatwić drugi.",
                    "Acabas de registrar tu primera medida. Un recordatorio a tiempo puede facilitar la segunda.",
                    "Du hast gerade deine erste Messung eingetragen. Eine passende Erinnerung macht die zweite leichter.",
                    "Vous venez d'enregistrer votre première mesure. Un rappel au bon moment peut faciliter la deuxième.",
                    "Você acabou de registrar sua primeira medição. Um lembrete no momento certo pode facilitar a segunda."
                ))
            }
    }
}
