/// Cel testow: Bazowa klasa dla testow snapshotowych, ktora izoluje je od preferencji zostawionych przez inne uruchomienia.
/// Dlaczego to wazne: Testy jednostkowe dzialaja wewnatrz aplikacji i czytaja jej prawdziwe UserDefaults, do ktorych pisza tez testy interfejsu (jezyk, premium, onboarding). Bez izolacji wyglad snapshotu zalezal od tego, co bylo uruchomione wczesniej.
/// Kryteria zaliczenia: Kazdy test startuje z pusta domena preferencji, a po nim wraca oryginal.

import XCTest
@testable import MeasureMe

@MainActor
class IsolatedPreferencesSnapshotTestCase: XCTestCase {
    private var savedPreferences: [String: Any]?

    /// Snapshot images depend on the toolchain that drew them - the same iOS runtime under a newer Xcode
    /// renders controls differently - so the baselines belong to CI's (Xcode 26.2, iOS 26.4.1). Elsewhere
    /// these tests are skipped rather than failing for reasons that are not bugs. Set
    /// MEASUREME_SNAPSHOT_TESTS=1 (in the scheme's environment) to run them on a matching toolchain.
    static let enableVariable = "MEASUREME_SNAPSHOT_TESTS"

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment[Self.enableVariable] == "1",
            "Snapshot baselines are recorded on CI's toolchain; set \(Self.enableVariable)=1 to run them here."
        )
        try super.setUpWithError()
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        savedPreferences = UserDefaults.standard.persistentDomain(forName: bundleID) ?? [:]
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        AppSettingsStore.shared.forceReloadSnapshot()
        AppLocalization.reloadLanguage()
    }

    override func tearDownWithError() throws {
        if let bundleID = Bundle.main.bundleIdentifier, let savedPreferences {
            UserDefaults.standard.setPersistentDomain(savedPreferences, forName: bundleID)
        }
        savedPreferences = nil
        AppSettingsStore.shared.forceReloadSnapshot()
        AppLocalization.reloadLanguage()
        try super.tearDownWithError()
    }
}
