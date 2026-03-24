/// Cel testow: Weryfikuje onboarding (kolejnosc krokow, akcje premium, linki prawne).
/// Dlaczego to wazne: Onboarding ustawia konfiguracje startowa; blad blokuje dalsze uzycie.
/// Kryteria zaliczenia: Kroki sa dostepne, mozna je przejsc, a kluczowe elementy sa widoczne.

import XCTest

final class OnboardingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        var launchArguments = ["-uiTestOnboardingMode"]
        if name.contains("testICloudBackupBoosterCanEnableBackupForPremiumUsers") {
            launchArguments.append("-uiTestForcePremium")
        }
        launchApp(arguments: launchArguments)
    }

    private func launchApp(arguments: [String]) {
        if app != nil, app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
        app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
    }

    private var nextButton: XCUIElement {
        app.buttons["UITest Next"].firstMatch
    }

    private var backButton: XCUIElement {
        app.buttons["UITest Back"].firstMatch
    }

    private var skipButton: XCUIElement {
        app.buttons["UITest Skip"].firstMatch
    }

    @MainActor
    /// Co sprawdza: Sprawdza scenariusz: WelcomeGoalAccessibilityValueReflectsSelection.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Wszystkie asercje XCTest sa spelnione, a test konczy sie bez bledu.
    func testWelcomeGoalAccessibilityValueReflectsSelection() {
        let goalIDs = [
            "onboarding.goal.loseWeight",
            "onboarding.goal.buildMuscle",
            "onboarding.goal.trackHealth"
        ]

        guard let goalButton = goalIDs
            .map({ app.buttons[$0] })
            .first(where: { $0.waitForExistence(timeout: 10) }) else {
            XCTFail("Expected at least one onboarding goal button")
            return
        }

        goalButton.tap()
        let value = goalButton.value as? String
        XCTAssertNotNil(value, "Cel powinien udostepniac wartosc dostepnosci")
        XCTAssertFalse((value ?? "").isEmpty, "Wartosc dostepnosci nie powinna byc pusta")
    }

    @MainActor
    /// Co sprawdza: Sprawdza scenariusz: NavigateThroughAllStepsSequentially.
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Asercje na elementach UI przechodza (m.in. `onboarding.next`).
    func testNavigateThroughAllStepsSequentially() {
        // powitanie -> profil -> boostery -> premium
        for _ in 0..<3 {
            let next = nextButton
            XCTAssertTrue(next.waitForExistence(timeout: 10), "Przycisk Dalej powinien istniec")
            XCTAssertTrue(next.isEnabled, "Przycisk Dalej powinien byc aktywny")
            next.tap()
        }

        let nextOnPremium = nextButton
        XCTAssertTrue(nextOnPremium.waitForExistence(timeout: 5), "Przycisk Dalej powinien istniec na kroku premium")
        XCTAssertTrue(nextOnPremium.isEnabled, "Przycisk Dalej powinien byc aktywny na kroku premium")
    }

    @MainActor
    /// Co sprawdza: Sprawdza scenariusz: PremiumStepShowsLegalLinksAndRestoreAction.
    /// Dlaczego: Zapewnia stabilny gating premium i poprawne odblokowanie funkcji.
    /// Kryteria: Asercje na elementach UI przechodza (m.in. `onboarding.next`, `onboarding.premium.restore`, `onboarding.premium.privacy`).
    func testPremiumStepShowsLegalLinksAndRestoreAction() {
        // powitanie -> profil -> boostery -> premium
        for _ in 0..<3 {
            let next = nextButton
            XCTAssertTrue(next.waitForExistence(timeout: 10), "Przycisk Dalej powinien istniec")
            next.tap()
        }

        let restore = app.buttons["onboarding.premium.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5), "Akcja przywrocenia zakupow powinna byc widoczna na kroku premium")

        let privacyLink = app.descendants(matching: .any)["onboarding.premium.privacy"]
        XCTAssertTrue(privacyLink.waitForExistence(timeout: 5), "Link do polityki prywatnosci powinien byc widoczny na kroku premium")

        let termsLink = app.descendants(matching: .any)["onboarding.premium.terms"]
        XCTAssertTrue(termsLink.waitForExistence(timeout: 5), "Link do warunkow uzycia powinien byc widoczny na kroku premium")
    }

    @MainActor
    func testPremiumTrialActivationFromOnboardingShowsPostPurchaseSetup() {
        launchApp(arguments: ["-uiTestOnboardingMode", "-uiTestSimulateTrialActivation"])

        for _ in 0..<3 {
            let next = nextButton
            XCTAssertTrue(next.waitForExistence(timeout: 10), "Przycisk Dalej powinien istniec")
            next.tap()
        }

        let trialButton = app.buttons["onboarding.premium.trial"].firstMatch
        XCTAssertTrue(trialButton.waitForExistence(timeout: 5), "CTA triala powinno byc widoczne na kroku premium")
        XCTAssertTrue(trialButton.isEnabled, "CTA triala powinno byc aktywne na kroku premium")
        trialButton.tap()

        let postPurchaseSheet = app.otherElements["postpurchase.sheet"].firstMatch
        XCTAssertTrue(postPurchaseSheet.waitForExistence(timeout: 5), "Aktywacja z onboardingu powinna pokazac ekran post-purchase setup")
    }

    @MainActor
    /// Co sprawdza: Sprawdza, ze RemindersButtonOpensSheet dziala poprawnie (otwarcie i podstawowe warunki).
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Asercje na elementach UI przechodza (m.in. `onboarding.next`, `onboarding.booster.reminders`, `onboarding.reminder.cancel`).
    func testRemindersButtonOpensSheet() {
        // powitanie -> profil -> boostery
        for _ in 0..<2 {
            let next = nextButton
            XCTAssertTrue(next.waitForExistence(timeout: 10))
            next.tap()
        }

        let remindersButton = app.buttons["onboarding.booster.reminders"]
        XCTAssertTrue(remindersButton.waitForExistence(timeout: 5), "Przycisk boostera przypomnien powinien istniec")
        remindersButton.tap()

        let sheet = app.otherElements["onboarding.reminder.sheet.visible"]
        let cancel = app.buttons["onboarding.reminder.cancel"]
        let confirm = app.buttons["onboarding.reminder.confirm"]
        XCTAssertTrue(
            sheet.waitForExistence(timeout: 5)
                || cancel.waitForExistence(timeout: 5)
                || confirm.waitForExistence(timeout: 5),
                      "Arkusz konfiguracji przypomnien powinien sie pojawic")
        if cancel.exists {
            cancel.tap()
        }
    }

    @MainActor
    func testICloudBackupBoosterShowsPremiumCTAForNonPremiumUsers() {
        for _ in 0..<2 {
            let next = nextButton
            XCTAssertTrue(next.waitForExistence(timeout: 10))
            next.tap()
        }

        let iCloudButton = app.buttons["onboarding.booster.icloud"]
        XCTAssertTrue(iCloudButton.waitForExistence(timeout: 5), "Przycisk boostera iCloud powinien istniec")
        iCloudButton.tap()

        let paywallCloseButton = app.buttons["premium.paywall.close"].firstMatch
        XCTAssertTrue(paywallCloseButton.waitForExistence(timeout: 5), "Booster iCloud powinien otworzyc paywall dla uzytkownika bez Premium")
    }

    @MainActor
    func testICloudBackupBoosterCanEnableBackupForPremiumUsers() {
        for _ in 0..<2 {
            let next = nextButton
            XCTAssertTrue(next.waitForExistence(timeout: 10))
            next.tap()
        }

        let iCloudButton = app.buttons["onboarding.booster.icloud"]
        XCTAssertTrue(iCloudButton.waitForExistence(timeout: 5), "Przycisk boostera iCloud powinien istniec")
        iCloudButton.tap()

        XCTAssertTrue(app.staticTexts["icloudEnabled:true"].firstMatch.waitForExistence(timeout: 5), "Uzytkownik Premium powinien moc wlaczyc backup iCloud z onboardingu")
    }

    @MainActor
    func testSkipOnBoostersPersistsICloudDecisionAndMovesToPremiumStep() {
        for _ in 0..<2 {
            let next = nextButton
            XCTAssertTrue(next.waitForExistence(timeout: 10))
            next.tap()
        }

        XCTAssertTrue(skipButton.waitForExistence(timeout: 5))
        skipButton.tap()

        XCTAssertTrue(app.staticTexts["step:3"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["icloudViewed:true"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["icloudSkipped:true"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["icloudEnabled:false"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    /// Co sprawdza: Sprawdza, ze elementy UI sa widoczne zgodnie z oczekiwaniem (PrivacyNoteVisibleOnWelcome).
    /// Dlaczego: Zapewnia przewidywalne zachowanie i latwiejsze diagnozowanie bledow.
    /// Kryteria: Asercje na elementach UI przechodza (m.in. `onboarding.privacy.note`).
    func testPrivacyNoteVisibleOnWelcome() {
        let privacyNote = app.descendants(matching: .any)["onboarding.privacy.note"].firstMatch
        let privacyCopy = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Your data stays on this device by default")
        ).firstMatch
        let privacyHookCopy = app.staticTexts["Privacy note"].firstMatch

        XCTAssertTrue(
            privacyNote.waitForExistence(timeout: 10)
                || privacyCopy.waitForExistence(timeout: 10)
                || privacyHookCopy.waitForExistence(timeout: 10),
            "Notatka o prywatnosci powinna byc widoczna na ekranie powitalnym onboardingu"
        )
    }
}
