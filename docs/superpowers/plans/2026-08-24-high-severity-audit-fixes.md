# High-Severity Audit Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the seven High-severity findings from the August 2026 MeasureMe audit — wrong behaviour a user will hit and notice, or data landing somewhere it shouldn't.

**Architecture:** Seven independent tasks, each touching one subsystem. No shared state between them, so they can be done in any order and reviewed separately. Six are fixes; Task 7 is a reproduction task that may end in withdrawing the finding rather than changing code. Where a behaviour is testable it is driven by a test first; where it lives inside a SwiftUI `body` the decision is extracted into a pure function and that function is tested (see the `swiftui-view-state-not-testable` project memory — `@State` writes on a non-installed `View` vanish, so testing the view directly passes vacuously).

**Tech Stack:** Swift 5 language mode, SwiftUI, SwiftData, XCTest, WidgetKit, UserNotifications, LocalAuthentication.

**Spec:** The audit report artifact — https://claude.ai/code/artifact/cab1fc28-f090-448a-9de7-8784b915753d — section "High", plus the `app-audit-2026-08` project memory.

## Global Constraints

- iOS deployment target is `17.2`. Any iOS 18+/26+ API must sit behind `#available`.
- `SWIFT_VERSION = 5.0` with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Do not enable Swift 6 mode as part of this work.
- Six localizations — `en, pl, es, de, fr, pt-BR` — at **exact** key parity. `MeasureMeTests/LocalizationConsistencyTests` fails the build on any drift. Every new user-facing string goes into all six `.strings` files in the same commit.
- No new third-party dependencies.
- Nothing may be added to `AppSettingsSnapshot.registeredDefaults` for a key that any `AppSettingsMigration` step inspects with `object(forKey:) == nil` — `NSRegistrationDomain` is process-wide and reads through, which silently disables the guard. See the `settings-store-write-diffing` memory.
- Build/test command (the toolchain is not on the default `xcode-select` path):

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild test -scheme MeasureMe \
  -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' \
  -derivedDataPath /tmp/mm-high-dd \
  -only-testing:MeasureMeTests/<SuiteName>
```

- **Snapshot baselines are stale on iOS 27.** A full `MeasureMeTests` run has a standing **17 failing test cases across 7 suites** (`HealthIndicatorDetailSnapshotTests`, `HomeViewSnapshotTests`, `DataSettingsDetailViewSnapshotTests`, `MetricDetailSnapshotTests`, `ExperienceSettingsDetailViewSnapshotTests`, `MeasurementsIndicatorsSnapshotTests`, `ComparePhotosSnapshotTests`). Never judge a run by the absolute failure count. To prove a task added nothing, run the full suite at the merge base in a throwaway worktree and set-difference the failing sets:

```bash
git worktree add /tmp/mm-base HEAD --detach
# run full MeasureMeTests in both trees with separate -derivedDataPath, then:
comm -23 /tmp/branch-failures.txt /tmp/base-failures.txt   # must be empty
```

- `-only-testing` with a class name that does not exist matches zero tests and still reports `** TEST SUCCEEDED **`. Always check the `Executed N tests` line against the number you expected.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `MeasureMeWidget/MeasureMeWidgetBundle.swift` | Widget gallery names/descriptions | 1 |
| `MeasureMeWidget/<lang>.lproj/Localizable.strings` (×6) | Widget gallery translations | 1 |
| `MeasureMeTests/LocalizationConsistencyTests.swift` | Adds coverage check for widget gallery literals | 1 |
| `MeasureMe/AppRuntimeConfigurator.swift` | Scopes the global `selectAll` hook | 2 |
| `MeasureMeTests/TextFieldSelectionPolicyTests.swift` (new) | Pure policy test for the hook | 2 |
| `MeasureMe/AppLog.swift` | Diagnostics-logging default | 3 |
| `MeasureMe/HealthKitManager.swift` | Drops a health value from a persisted log line | 3 |
| `MeasureMe/ActiveFiltersView.swift` | Removes a leftover debug log | 3 |
| `MeasureMe/SettingsStore/AppSettingsSnapshot.swift` | Diagnostics + insight defaults | 3 |
| `MeasureMe/Features/Settings/Sections/AboutSettingsDetailView.swift` | Diagnostics toggle default | 3 |
| `MeasureMe/MetricInsightService.swift` | Insight cache key + day boundary + store location | 4 |
| `MeasureMe/AppGlass.swift` | Reduce Transparency for every glass surface | 5 |
| `MeasureMeTests/AppGlassBackgroundTests.swift` (new) | Pure fill-policy test | 5 |
| `MeasureMe/NotificationManager.swift` | Re-schedule entry point | 6 |
| `MeasureMe/Features/Settings/Sections/LanguageSettingsDetailView.swift` | Calls it on language change | 6 |

---

### Task 1: Widget gallery strings are missing from every locale

Two of the three widgets pass literals to `configurationDisplayName` / `description` that exist in **no** `.strings` file, so Polish, German, Spanish, French and Brazilian Portuguese users see English in the widget gallery. `LocalizationConsistencyTests` cannot catch this: it compares locales against each other, and the keys are absent from all six equally.

**Files:**
- Modify: `MeasureMeWidget/en.lproj/Localizable.strings` (and `pl`, `es`, `de`, `fr`, `pt-BR`)
- Modify: `MeasureMeTests/LocalizationConsistencyTests.swift`
- Reference (unchanged): `MeasureMeWidget/MeasureMeWidgetBundle.swift:26,27,43,44,60,61`

**Interfaces:**
- Consumes: `parseStringsFile(named:table:)` — existing private helper in `LocalizationConsistencyTests`, returns a value with a `.values: [String: String]` property.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Write the failing test**

Add to `MeasureMeTests/LocalizationConsistencyTests.swift`:

```swift
    /// `configurationDisplayName` / `description` take a literal that WidgetKit localizes
    /// through the extension's own bundle. Parity testing cannot see a key that is missing
    /// from every locale at once, so check the source literals against the catalog directly.
    func testWidgetGalleryLiteralsExistInEveryLocalization() throws {
        let bundleSource = try String(
            contentsOf: repositoryRoot().appendingPathComponent("MeasureMeWidget/MeasureMeWidgetBundle.swift"),
            encoding: .utf8
        )

        let pattern = #"\.(?:configurationDisplayName|description)\("([^"]+)"\)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(bundleSource.startIndex..., in: bundleSource)
        let literals = regex.matches(in: bundleSource, range: range).compactMap { match -> String? in
            guard let r = Range(match.range(at: 1), in: bundleSource) else { return nil }
            return String(bundleSource[r])
        }

        XCTAssertEqual(literals.count, 6, "Expected three widgets × (name + description).")

        for languageCode in supportedLanguages {
            let catalog = try parseStringsFile(named: languageCode, table: "widget.localizable")
            let missing = literals.filter { catalog.values[$0] == nil }.sorted()
            XCTAssertTrue(
                missing.isEmpty,
                "Widget gallery strings missing from \(languageCode): \(missing.joined(separator: " | "))"
            )
        }
    }
```

`repositoryRoot()` does not exist yet. Add it next to `parseStringsFile`:

```swift
    private func repositoryRoot() -> URL {
        // .../MeasureMeTests/LocalizationConsistencyTests.swift -> repository root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild test -scheme MeasureMe \
  -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' \
  -derivedDataPath /tmp/mm-high-dd \
  -only-testing:MeasureMeTests/LocalizationConsistencyTests
```

Expected: FAIL, six times (once per locale), listing `Automatically picks the metric that needs your attention. | Shows your current streak and logging status. | Smart Metric | Streak`.

- [ ] **Step 3: Add the four missing keys to all six catalogs**

Append to `MeasureMeWidget/en.lproj/Localizable.strings`:

```
"Smart Metric" = "Smart Metric";
"Automatically picks the metric that needs your attention." = "Automatically picks the metric that needs your attention.";
"Streak" = "Streak";
"Shows your current streak and logging status." = "Shows your current streak and logging status.";
```

`MeasureMeWidget/pl.lproj/Localizable.strings`:

```
"Smart Metric" = "Inteligentna metryka";
"Automatically picks the metric that needs your attention." = "Automatycznie wybiera metrykę, która wymaga uwagi.";
"Streak" = "Seria";
"Shows your current streak and logging status." = "Pokazuje aktualną serię i status zapisów.";
```

`MeasureMeWidget/de.lproj/Localizable.strings`:

```
"Smart Metric" = "Intelligente Messgröße";
"Automatically picks the metric that needs your attention." = "Wählt automatisch die Messgröße, die Aufmerksamkeit braucht.";
"Streak" = "Serie";
"Shows your current streak and logging status." = "Zeigt deine aktuelle Serie und den Eintragsstatus.";
```

`MeasureMeWidget/es.lproj/Localizable.strings`:

```
"Smart Metric" = "Métrica inteligente";
"Automatically picks the metric that needs your attention." = "Elige automáticamente la métrica que necesita tu atención.";
"Streak" = "Racha";
"Shows your current streak and logging status." = "Muestra tu racha actual y el estado de registro.";
```

`MeasureMeWidget/fr.lproj/Localizable.strings`:

```
"Smart Metric" = "Mesure intelligente";
"Automatically picks the metric that needs your attention." = "Choisit automatiquement la mesure qui demande votre attention.";
"Streak" = "Série";
"Shows your current streak and logging status." = "Affiche votre série en cours et l'état des saisies.";
```

`MeasureMeWidget/pt-BR.lproj/Localizable.strings`:

```
"Smart Metric" = "Métrica inteligente";
"Automatically picks the metric that needs your attention." = "Escolhe automaticamente a métrica que precisa da sua atenção.";
"Streak" = "Sequência";
"Shows your current streak and logging status." = "Mostra sua sequência atual e o status dos registros.";
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the command from Step 2. Expected: `Executed 6 tests, with 0 failures` — the five pre-existing parity tests plus the new one. The parity test must also stay green, which it will because all six catalogs gained the same four keys.

- [ ] **Step 5: Commit**

```bash
git add MeasureMeWidget/*.lproj/Localizable.strings MeasureMeTests/LocalizationConsistencyTests.swift
git commit -m "fix(widget): localize the Smart Metric and Streak gallery entries"
```

---

### Task 2: Every text field in the app selects all of its text on focus

`installTextFieldSelectionBehaviorIfNeeded` registers a process-wide `UITextField.textDidBeginEditingNotification` observer that calls `selectAll(nil)` on whatever field gains focus. It is meant for numeric measurement entry, where tap-and-overwrite is right. It also hits the Settings search field, the AI question composer, the profile name and the custom-metric name — tap in to fix one character and the next keystroke wipes the field.

Every genuinely numeric field in the app sets `.keyboardType(.decimalPad)` (verified across `MetricDetailComponents.swift`, `ProfileSettingsSection.swift`, `CustomMetricEditorView.swift`, `AgeSettingsView.swift`, `HeightSettingsView.swift`), so the keyboard type is a reliable discriminator and needs no per-call-site changes.

**Files:**
- Modify: `MeasureMe/AppRuntimeConfigurator.swift:66-77`
- Create: `MeasureMeTests/TextFieldSelectionPolicyTests.swift`

**Interfaces:**
- Produces: `AppRuntimeConfigurator.shouldSelectAllOnFocus(keyboardType:) -> Bool` — `static`, `nonisolated`, takes a `UIKeyboardType`.

- [ ] **Step 1: Write the failing test**

Create `MeasureMeTests/TextFieldSelectionPolicyTests.swift`:

```swift
/// Cel testow: Auto-zaznaczanie całej treści przy fokusie ma dotyczyć wyłącznie pól liczbowych.
/// Dlaczego to wazne: Globalny hook kasował treść pola wyszukiwania i kompozytora pytań do AI.
/// Kryteria zaliczenia: Tylko klawiatury liczbowe kwalifikują się do selectAll.

import XCTest
import UIKit
@testable import MeasureMe

final class TextFieldSelectionPolicyTests: XCTestCase {
    func testNumericKeyboardsSelectAllOnFocus() {
        XCTAssertTrue(AppRuntimeConfigurator.shouldSelectAllOnFocus(keyboardType: .decimalPad))
        XCTAssertTrue(AppRuntimeConfigurator.shouldSelectAllOnFocus(keyboardType: .numberPad))
    }

    func testTextKeyboardsKeepTheCaretWhereTheUserTapped() {
        // The Settings search field, the AI question composer, the profile name and the
        // custom-metric name all use a text keyboard; selecting all discards what they typed.
        XCTAssertFalse(AppRuntimeConfigurator.shouldSelectAllOnFocus(keyboardType: .default))
        XCTAssertFalse(AppRuntimeConfigurator.shouldSelectAllOnFocus(keyboardType: .emailAddress))
        XCTAssertFalse(AppRuntimeConfigurator.shouldSelectAllOnFocus(keyboardType: .webSearch))
        XCTAssertFalse(AppRuntimeConfigurator.shouldSelectAllOnFocus(keyboardType: .asciiCapable))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild test -scheme MeasureMe \
  -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' \
  -derivedDataPath /tmp/mm-high-dd \
  -only-testing:MeasureMeTests/TextFieldSelectionPolicyTests
```

Expected: FAIL to compile — `type 'AppRuntimeConfigurator' has no member 'shouldSelectAllOnFocus'`.

- [ ] **Step 3: Write the implementation**

In `MeasureMe/AppRuntimeConfigurator.swift`, replace the body of `installTextFieldSelectionBehaviorIfNeeded` and add the policy function:

```swift
    /// Tap-and-overwrite is right for measurement entry and wrong everywhere else: on a text
    /// field, selecting all on focus means the next keystroke discards what the person typed.
    nonisolated static func shouldSelectAllOnFocus(keyboardType: UIKeyboardType) -> Bool {
        switch keyboardType {
        case .decimalPad, .numberPad:
            return true
        default:
            return false
        }
    }

    private static func installTextFieldSelectionBehaviorIfNeeded(isUnitTestHostMode: Bool) {
        guard !isUnitTestHostMode else { return }

        NotificationCenter.default.addObserver(
            forName: UITextField.textDidBeginEditingNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let textField = notification.object as? UITextField,
                  shouldSelectAllOnFocus(keyboardType: textField.keyboardType) else { return }
            DispatchQueue.main.async { textField.selectAll(nil) }
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run the command from Step 2. Expected: `Executed 2 tests, with 0 failures`.

- [ ] **Step 5: Verify the behaviour in the simulator**

This is the one task whose whole point is interaction, so confirm it rather than trusting the unit test:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -scheme MeasureMe -configuration Debug \
  -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' \
  -derivedDataPath /tmp/mm-high-dd build
```

Launch the built `.app` on the simulator, then:
1. Settings → search field: type `rem`, tap away, tap back in, type `i`. Expected `remi`, not `i`.
2. Settings → Profile → name: same check.
3. Any metric detail → goal value field: tap in. Expected the existing number **is** fully selected.

- [ ] **Step 6: Commit**

```bash
git add MeasureMe/AppRuntimeConfigurator.swift MeasureMeTests/TextFieldSelectionPolicyTests.swift
git commit -m "fix(input): only auto-select numeric fields on focus"
```

---

### Task 3: Diagnostic logging is on by default in release and captures a health value

`AppLog.shouldPersistLogs` returns `true` when `diagnostics_logging_enabled` was never written, so release builds buffer logs by default into `CrashReporter`, which flushes to `Application Support/CrashReports/latest_log.txt` and is offered to the user as a shareable report. `HealthKitManager.swift:784` puts a real measurement into that buffer. `ActiveFiltersView.swift:87` still carries a leftover `AppLog.debug("Clear all")`.

**Decision taken here — flag it in review if you disagree:** the default flips to **off**, matching the analytics consent decision already shipped. Support flow becomes "ask the person to enable Diagnostics logging in Settings → About, reproduce, then share", which costs one round trip but means an unasked-for log file is never sitting in the container. Reverting is a one-line change to `registeredDefaults`.

**Files:**
- Modify: `MeasureMe/AppLog.swift:6-16`
- Modify: `MeasureMe/SettingsStore/AppSettingsSnapshot.swift:227,356`
- Modify: `MeasureMe/Features/Settings/Sections/AboutSettingsDetailView.swift:4`
- Modify: `MeasureMe/HealthKitManager.swift:784`
- Modify: `MeasureMe/ActiveFiltersView.swift:87`
- Modify: `MeasureMeTests/AppSettingsStoreTests.swift:420`

**Interfaces:**
- Produces: no new symbols. `AppSettingsKeys.Diagnostics.diagnosticsLoggingEnabled` keeps its name and stays **out** of any migration `object(forKey:) == nil` guard, so leaving it in `registeredDefaults` is safe.

- [ ] **Step 1: Write the failing test**

Add to `MeasureMeTests/AppSettingsStoreTests.swift`:

```swift
    func testDiagnosticsLoggingIsOffUntilTheUserAsksForIt() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)

        // The buffer this flag drives is written to disk and offered as a shareable report,
        // so it must not fill up before anyone asked for it.
        XCTAssertFalse(store.snapshot.diagnostics.diagnosticsLoggingEnabled)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild test -scheme MeasureMe \
  -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' \
  -derivedDataPath /tmp/mm-high-dd \
  -only-testing:MeasureMeTests/AppSettingsStoreTests/testDiagnosticsLoggingIsOffUntilTheUserAsksForIt
```

Expected: FAIL — `XCTAssertFalse failed`.

- [ ] **Step 3: Flip the default and stop logging the health value**

`MeasureMe/SettingsStore/AppSettingsSnapshot.swift:227`:

```swift
        AppSettingsKeys.Diagnostics.diagnosticsLoggingEnabled: false,
```

`MeasureMe/SettingsStore/AppSettingsSnapshot.swift:356`:

```swift
                diagnosticsLoggingEnabled: defaults.object(forKey: AppSettingsKeys.Diagnostics.diagnosticsLoggingEnabled) as? Bool ?? false,
```

`MeasureMe/AppLog.swift` — replace `shouldPersistLogs`:

```swift
    private nonisolated static var shouldPersistLogs: Bool {
        #if DEBUG
        return true
        #else
        // Opt-in: the buffer ends up in a file the person can mail out, so an absent
        // preference means "no", not "yes".
        return UserDefaults.standard.bool(forKey: diagnosticsLoggingEnabledKey)
        #endif
    }
```

`MeasureMe/Features/Settings/Sections/AboutSettingsDetailView.swift:4`:

```swift
    @AppSetting(\.diagnostics.diagnosticsLoggingEnabled) private var diagnosticsLoggingEnabled: Bool = false
```

`MeasureMe/HealthKitManager.swift:784` — drop the value:

```swift
            AppLog.debug("✅ Imported height from HealthKit")
```

`MeasureMe/ActiveFiltersView.swift:87` — delete the line `AppLog.debug("Clear all")` entirely (it logs nothing useful and is a development leftover).

- [ ] **Step 4: Update the test that asserted the old default**

`MeasureMeTests/AppSettingsStoreTests.swift:420`, inside `testClearUserDataDefaultsClearsProfileAndNotificationState`, change:

```swift
        XCTAssertTrue(store.snapshot.diagnostics.diagnosticsLoggingEnabled)
```

to:

```swift
        // Clearing user data returns the flag to its default, which is now off.
        XCTAssertFalse(store.snapshot.diagnostics.diagnosticsLoggingEnabled)
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild test -scheme MeasureMe \
  -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' \
  -derivedDataPath /tmp/mm-high-dd \
  -only-testing:MeasureMeTests/AppSettingsStoreTests \
  -only-testing:MeasureMeTests/HealthKitManagerImportMappingTests
```

Expected: `Executed 25 tests, with 0 failures` for `AppSettingsStoreTests` — 24 existing plus the one added in Step 1; the amended assertion is not an extra test. No failures in the HealthKit mapping suite.

- [ ] **Step 6: Commit**

```bash
git add MeasureMe/AppLog.swift MeasureMe/SettingsStore/AppSettingsSnapshot.swift \
        MeasureMe/Features/Settings/Sections/AboutSettingsDetailView.swift \
        MeasureMe/HealthKitManager.swift MeasureMe/ActiveFiltersView.swift \
        MeasureMeTests/AppSettingsStoreTests.swift
git commit -m "fix(privacy): make diagnostics logging opt-in and stop logging a health value"
```

---

### Task 4: The AI insight cache puts measurements in a shared-container plist key

`InsightDiskCache.stableKey` builds `v{promptVersion}_{metricTitle}_{latestValueText}_{YYYY-MM-DD}` and stores entries under `insight_disk_cache_v1` in the `group.com.jacek.measureme` UserDefaults — the App Group container shared with the widget and watch processes, and the one place `DatabaseEncryption` never touches. The person's actual measurements end up as plaintext dictionary keys.

The same line carries a second bug: the date comes from `ISO8601DateFormatter()`, which is UTC, so the "daily" cache rolls over at UTC midnight — mid-morning for users east of Greenwich, mid-afternoon in New Zealand.

Nothing outside the app reads this cache (verified: `InsightDiskCache` appears only in `MeasureMe/MetricInsightService.swift` and its tests), so it also moves out of the App Group.

**Files:**
- Modify: `MeasureMe/MetricInsightService.swift:124-146`
- Modify: `MeasureMeTests/InsightDiskCacheTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `InsightDiskCache.stableKey(metricTitle:latestValueText:promptVersion:) -> String` keeps its signature; only the returned format changes. `InsightDiskCache.suiteName` keeps its `#if DEBUG`-mutable form so the existing tests keep overriding it.

- [ ] **Step 1: Write the failing test**

Add to `MeasureMeTests/InsightDiskCacheTests.swift`:

```swift
    func testStableKeyDoesNotContainTheMeasurementValue() {
        let key = InsightDiskCache.stableKey(
            metricTitle: "Weight",
            latestValueText: "82.4 kg",
            promptVersion: "7"
        )

        // The key becomes a plaintext dictionary key inside a plist on disk.
        XCTAssertFalse(key.contains("82.4"))
        XCTAssertFalse(key.contains("kg"))
        XCTAssertTrue(key.hasPrefix("v7_"))
    }

    func testStableKeyChangesWhenTheValueChanges() {
        let a = InsightDiskCache.stableKey(metricTitle: "Weight", latestValueText: "82.4 kg", promptVersion: "7")
        let b = InsightDiskCache.stableKey(metricTitle: "Weight", latestValueText: "82.5 kg", promptVersion: "7")

        XCTAssertNotEqual(a, b, "A new measurement must still invalidate the cached insight.")
    }

    func testStableKeyRollsOverOnTheLocalDayNotUTC() {
        // 2026-08-24 23:30 in Warsaw is 21:30 UTC on the same day; 2026-08-25 01:30 Warsaw is
        // 23:30 UTC on the 24th. A UTC-derived day gives those two the same key, which is what
        // made the "daily" insight reset mid-morning for anyone east of Greenwich.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!

        let lateEvening = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 23, minute: 30))!
        let afterMidnight = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 1, minute: 30))!

        let a = InsightDiskCache.dayComponent(for: lateEvening, calendar: calendar)
        let b = InsightDiskCache.dayComponent(for: afterMidnight, calendar: calendar)

        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a, "2026-08-24")
        XCTAssertEqual(b, "2026-08-25")
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild test -scheme MeasureMe \
  -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' \
  -derivedDataPath /tmp/mm-high-dd \
  -only-testing:MeasureMeTests/InsightDiskCacheTests
```

Expected: FAIL to compile — `type 'InsightDiskCache' has no member 'dayComponent'`.

- [ ] **Step 3: Write the implementation**

In `MeasureMe/MetricInsightService.swift`, add `import CryptoKit` at the top of the file if it is not already imported, then replace `suiteName` and `stableKey`:

```swift
    #if DEBUG
    nonisolated(unsafe) static var suiteName = defaultSuiteName
    #else
    static let suiteName = defaultSuiteName
    #endif

    /// Deliberately **not** the App Group: nothing outside the app reads this cache, and the
    /// shared container is the one place `DatabaseEncryption` never covers.
    private static let defaultSuiteName = "com.jacek.measureme.insights"

    /// Local calendar day. `ISO8601DateFormatter` is UTC, which rolled the "daily" cache over
    /// mid-morning for anyone east of Greenwich.
    static func dayComponent(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Stable cache key that survives app restarts.
    ///
    /// The metric title and the latest value are hashed rather than interpolated: the key ends
    /// up as a plaintext dictionary key in a plist on disk, and the value is a measurement.
    static func stableKey(metricTitle: String, latestValueText: String, promptVersion: String) -> String {
        let material = "\(metricTitle)|\(latestValueText)|\(dayComponent(for: Date()))"
        let digest = SHA256.hash(data: Data(material.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "v\(promptVersion)_\(hex)"
    }
```

- [ ] **Step 4: Fix `removeEntries(matching:)`, which can no longer match on the title**

`removeEntries(matching metricTitle: String)` currently finds entries by substring on the key. Hashing breaks that. Because the store is small (`maxEntries = 80`) and this is a rare invalidation path, drop the whole store instead — the entries regenerate on next view:

```swift
    /// Hashed keys cannot be matched by metric, and the store is capped at `maxEntries`, so
    /// invalidating one metric clears the cache rather than scanning it.
    static func removeEntries(matching metricTitle: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.removeObject(forKey: storeKey)
    }
```

- [ ] **Step 5: Purge the entries already written into the App Group**

Add to `MeasureMe/MetricInsightService.swift`, and call it once from `AppLifecycleCoordinator.performDeferredStartup`:

```swift
    /// One-time cleanup of the pre-move cache, which held measurement values in its keys.
    static func purgeLegacyAppGroupCache() {
        guard let legacy = UserDefaults(suiteName: "group.com.jacek.measureme") else { return }
        legacy.removeObject(forKey: storeKey)
    }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run the command from Step 2, plus the two suites that exercise the cache end to end:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild test -scheme MeasureMe \
  -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' \
  -derivedDataPath /tmp/mm-high-dd \
  -only-testing:MeasureMeTests/InsightDiskCacheTests \
  -only-testing:MeasureMeTests/MetricInsightServiceCacheTests \
  -only-testing:MeasureMeTests/InsightConcurrencyTests
```

Expected: 0 failures. If `MetricInsightServiceCacheTests` asserts on key **shape** anywhere, update those assertions to the hashed form rather than reverting the implementation.

- [ ] **Step 7: Commit**

```bash
git add MeasureMe/MetricInsightService.swift MeasureMe/AppLifecycleCoordinator.swift \
        MeasureMeTests/InsightDiskCacheTests.swift
git commit -m "fix(privacy): hash insight cache keys, use the local day, leave the App Group"
```

---

### Task 5: Glass surfaces ignore Reduce Transparency

`AppGlassBackground` is the canonical surface of the app — 109 call sites. In dark mode it renders `.ultraThinMaterial` plus five stacked overlays and two shadows, and it reads `colorScheme` and nothing else. `accessibilityReduceTransparency` appears exactly once in the whole codebase, in `AppScreenBackground.swift:14`, so turning the setting on gives a flat page background behind 109 unchanged blur panels.

The light-mode branch is already almost exactly the right fallback — an opaque fill plus a border — so the fix reuses that shape.

**Files:**
- Modify: `MeasureMe/AppGlass.swift:173-337`
- Create: `MeasureMeTests/AppGlassBackgroundTests.swift`

**Interfaces:**
- Produces: `AppGlassBackground.usesOpaqueFill(colorScheme:reduceTransparency:) -> Bool` — `static`, `nonisolated`.

- [ ] **Step 1: Write the failing test**

Create `MeasureMeTests/AppGlassBackgroundTests.swift`:

```swift
/// Cel testow: Powierzchnie "glass" muszą respektować Reduce Transparency.
/// Dlaczego to wazne: To 109 miejsc w aplikacji; bez tego ustawienie systemowe nie robi nic.
/// Kryteria zaliczenia: Materiał jest używany wyłącznie w dark mode przy wyłączonym Reduce Transparency.

import XCTest
import SwiftUI
@testable import MeasureMe

final class AppGlassBackgroundTests: XCTestCase {
    func testDarkModeUsesMaterialOnlyWhenTransparencyIsAllowed() {
        XCTAssertFalse(AppGlassBackground.usesOpaqueFill(colorScheme: .dark, reduceTransparency: false))
        XCTAssertTrue(AppGlassBackground.usesOpaqueFill(colorScheme: .dark, reduceTransparency: true))
    }

    func testLightModeIsAlwaysOpaque() {
        XCTAssertTrue(AppGlassBackground.usesOpaqueFill(colorScheme: .light, reduceTransparency: false))
        XCTAssertTrue(AppGlassBackground.usesOpaqueFill(colorScheme: .light, reduceTransparency: true))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild test -scheme MeasureMe \
  -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' \
  -derivedDataPath /tmp/mm-high-dd \
  -only-testing:MeasureMeTests/AppGlassBackgroundTests
```

Expected: FAIL to compile — `type 'AppGlassBackground' has no member 'usesOpaqueFill'`.

- [ ] **Step 3: Write the implementation**

In `MeasureMe/AppGlass.swift`, inside `struct AppGlassBackground`, add the environment value and the policy, and route the existing dark-mode branches through it:

```swift
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Reduce Transparency removes the material and every gradient overlay, leaving the same
    /// flat fill + border the light appearance already uses.
    nonisolated static func usesOpaqueFill(colorScheme: ColorScheme, reduceTransparency: Bool) -> Bool {
        colorScheme != .dark || reduceTransparency
    }

    private var isOpaque: Bool {
        Self.usesOpaqueFill(colorScheme: colorScheme, reduceTransparency: reduceTransparency)
    }
```

Then replace every `colorScheme == .dark` test **inside `AppGlassBackground`** with `!isOpaque`. The properties to change are `backgroundFill`, `fillOverlayGradient`, `highlightStrokeGradient`, `innerStrokeColor`, `tintedOverlay`, `fillOverlay`, `highlightStroke`, `borderStroke`, and `baseBackground`. Leave `shadowColor` alone — see the note after the code. For example:

```swift
    private var backgroundFill: AnyShapeStyle {
        isOpaque
            ? AnyShapeStyle(AppColorRoles.surfacePrimary)
            : AnyShapeStyle(.ultraThinMaterial)
    }
```

and

```swift
    private var baseBackground: some View {
        Group {
            if isOpaque {
                // Flat fill + border only — no material, no gradients, no darkness wash.
                shape
                    .fill(backgroundFill)
                    .overlay(borderStroke)
            } else {
                shape
                    .fill(backgroundFill)
                    .overlay(tintedOverlay)
                    .overlay(fillOverlay)
                    .overlay(borderStroke)
                    .overlay(highlightStroke)
                    .overlay(innerStroke)
            }
        }
    }
```

Leave `shadowColor`'s use of `colorScheme` for picking `shadowStrong` vs `shadowSoft` — Reduce Transparency says nothing about shadows, and dropping them would flatten the hierarchy.

Do **not** touch `ClaudeLightStyle`, `LiquidCapsuleButtonStyle` or `LiquidSwitchToggleStyle` in this task; they are separate surfaces and belong to a follow-up.

- [ ] **Step 4: Run test to verify it passes**

Run the command from Step 2. Expected: `Executed 2 tests, with 0 failures`.

- [ ] **Step 5: Confirm the change is visible, and that it changed nothing by default**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -scheme MeasureMe -configuration Debug \
  -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' \
  -derivedDataPath /tmp/mm-high-dd build
```

On the simulator, with the app in dark mode: Settings → Accessibility → Display & Text Size → Reduce Transparency **off**, open Home, screenshot. Turn Reduce Transparency **on**, open Home, screenshot. The first must be unchanged from `main`; the second must show opaque cards.

- [ ] **Step 6: Run the full suite and set-difference against the merge base**

This task touches the surface behind 109 views, so the snapshot suites must be compared properly rather than eyeballed. Follow the procedure in Global Constraints. Expected: empty set-difference.

- [ ] **Step 7: Commit**

```bash
git add MeasureMe/AppGlass.swift MeasureMeTests/AppGlassBackgroundTests.swift
git commit -m "fix(a11y): honour Reduce Transparency on glass surfaces"
```

---

### Task 6: Scheduled notifications keep the language they were created in

`NotificationManager` bakes `content.title` and `content.body` at scheduling time through `AppLocalization.string` (`:304`, `:438`, `:561`). `LanguageSettingsDetailView.languageRow` sets `appLanguage` and calls `AppLocalization.reloadLanguage()`, which only clears the cached bundle — nothing rebuilds the pending requests. Daily and weekly reminders are repeating requests, so someone who switches from English to Polish keeps getting English reminders indefinitely.

**Scope limit, stated deliberately:** this rebuilds the three recurring kinds whose copy the person sees over and over — measurement reminders, the smart reminder, and the photo reminder. It does **not** rebuild `scheduleTrialEndingReminder` (a one-shot whose trigger date would reset, turning a language change into an extended trial) or the AI notifications (they need a `ModelContext` and are event-driven, so they pick up the new language on their next natural scheduling pass). Note this in the PR description.

**Files:**
- Modify: `MeasureMe/NotificationManager.swift`
- Modify: `MeasureMe/Features/Settings/Sections/LanguageSettingsDetailView.swift:34-38`
- Modify: `MeasureMeTests/NotificationManagerTests.swift`

**Interfaces:**
- Produces: `NotificationManager.rescheduleLocalizedNotifications()` — `@MainActor`, no arguments, no return.
- Consumes: existing `loadReminders()`, `scheduleAllReminders(_:)`, `scheduleSmartIfNeeded(context:)`, `schedulePhotoReminderIfNeeded()`, `cancelAllReminders()`.

**Verified signatures** (`MeasureMe/NotificationManager.swift`) — use these exactly:

```swift
struct MeasurementReminder: Identifiable, Codable, Hashable {
    let id: String
    let date: Date
    let repeatRule: ReminderRepeat            // .once | .daily | .weekly
    init(id: String = UUID().uuidString, date: Date, repeatRule: ReminderRepeat = .once)
}

func loadReminders() -> [MeasurementReminder]     // :266
func saveReminders(_ reminders: [MeasurementReminder])  // :279
func cancelAllReminders()                         // :335
func cancelSmartNotification()                    // :498
func cancelPhotoReminder()                        // :580
```

There is **no** `isEnabled` on `MeasurementReminder`.

- [ ] **Step 1: Write the failing test**

Add to `MeasureMeTests/NotificationManagerTests.swift`:

```swift
    /// Co sprawdza: Zmiana języka przebudowuje zaplanowane powiadomienia cykliczne.
    /// Dlaczego: Treść jest zamrażana w chwili planowania, więc bez tego użytkownik dostaje
    ///   przypomnienia w poprzednim języku aż do następnej edycji.
    /// Kryteria: Po przełączeniu języka tytuł oczekującego żądania jest w nowym języku.
    func testRescheduleLocalizedNotificationsRebuildsReminderCopy() async throws {
        let manager = NotificationManager.shared
        AppSettingsStore.shared.set(\.experience.appLanguage, "en")
        AppLocalization.reloadLanguage()

        // The title interpolates the profile name, so clear it to keep the assertion about
        // language rather than about whatever the shared store happens to hold.
        let previousName = AppSettingsStore.shared.snapshot.profile.userName
        AppSettingsStore.shared.set(\.profile.userName, "")

        let reminder = MeasurementReminder(
            date: Date().addingTimeInterval(3_600),
            repeatRule: .daily
        )
        manager.saveReminders([reminder])
        manager.scheduleAllReminders([reminder])

        let englishTitle = try await pendingTitle(forPrefix: reminder.id)

        AppSettingsStore.shared.set(\.experience.appLanguage, "pl")
        AppLocalization.reloadLanguage()
        manager.rescheduleLocalizedNotifications()

        let polishTitle = try await pendingTitle(forPrefix: reminder.id)

        XCTAssertNotEqual(englishTitle, polishTitle)
        XCTAssertEqual(polishTitle, AppLocalization.string("notification.log.title", "").capitalizingNotificationStart())

        manager.cancelAllReminders()
        manager.saveReminders([])
        AppSettingsStore.shared.set(\.profile.userName, previousName)
        AppSettingsStore.shared.set(\.experience.appLanguage, "system")
        AppLocalization.reloadLanguage()
    }

    private func pendingTitle(forPrefix prefix: String) async throws -> String {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let match = try XCTUnwrap(requests.first { $0.identifier.hasPrefix(prefix) })
        return match.content.title
    }
```

If `MeasurementReminder`'s initializer differs, match the shape already used elsewhere in `NotificationManagerTests.swift` rather than inventing one. The reminder title format string is `notification.log.title` with one argument (see `NotificationManager.swift:304`); pass whatever prefix argument the production call passes.

- [ ] **Step 2: Run test to verify it fails**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild test -scheme MeasureMe \
  -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' \
  -derivedDataPath /tmp/mm-high-dd \
  -only-testing:MeasureMeTests/NotificationManagerTests/testRescheduleLocalizedNotificationsRebuildsReminderCopy
```

Expected: FAIL to compile — `value of type 'NotificationManager' has no member 'rescheduleLocalizedNotifications'`.

- [ ] **Step 3: Write the implementation**

Add to `MeasureMe/NotificationManager.swift`:

```swift
    /// Rebuilds the recurring notifications whose copy is frozen at scheduling time.
    ///
    /// Call after the in-app language changes. Deliberately excludes the trial-ending reminder
    /// (a one-shot whose trigger date would reset) and the AI notifications (event-driven, and
    /// they need a ModelContext) — both pick the new language up on their next scheduling pass.
    func rescheduleLocalizedNotifications() {
        let reminders = loadReminders()
        cancelAllReminders()
        scheduleAllReminders(reminders)

        cancelSmartNotification()
        scheduleSmartIfNeeded()

        cancelPhotoReminder()
        schedulePhotoReminderIfNeeded()
    }
```

And in `MeasureMe/Features/Settings/Sections/LanguageSettingsDetailView.swift`, inside `languageRow`'s action:

```swift
        Button {
            appLanguage = value
            AppLocalization.reloadLanguage()
            // Notification copy is baked when the request is scheduled, so pending recurring
            // reminders would otherwise stay in the previous language forever.
            NotificationManager.shared.rescheduleLocalizedNotifications()
            Haptics.selection()
        } label: {
```

- [ ] **Step 4: Run test to verify it passes**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 5: Run the whole notification suite**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild test -scheme MeasureMe \
  -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' \
  -derivedDataPath /tmp/mm-high-dd \
  -only-testing:MeasureMeTests/NotificationManagerTests
```

Expected: 0 failures. The suite shares one `UNUserNotificationCenter` across tests, so if the new test leaks pending requests into a neighbour, fix the teardown rather than the neighbour.

- [ ] **Step 6: Commit**

```bash
git add MeasureMe/NotificationManager.swift \
        MeasureMe/Features/Settings/Sections/LanguageSettingsDetailView.swift \
        MeasureMeTests/NotificationManagerTests.swift
git commit -m "fix(i18n): rebuild recurring notifications when the app language changes"
```

---

### Task 7: Reproduce — or withdraw — the UIKit chrome theming finding

**This task may end with no code change.** The audit claims that because `configureGlobalAppearance()` runs once from `MeasureMeApp.init()`, the nav bar and tab bar can sit in the opposite appearance from the content when the person forces light or dark via the in-app `appAppearance` setting.

Re-reading the code casts doubt on it. `AppColorRoles.dynamic(light:dark:)` builds `UIColor(dynamicProvider:)`, which resolves against the trait collection **at draw time**, not at configuration time. And in a SwiftUI-lifecycle app, `.preferredColorScheme` on the `WindowGroup` root propagates to the hosting window, so UIKit bars should follow. The finding was written from source reading and was explicitly flagged in the report as needing runtime confirmation. Confirm it before touching anything.

**Files:**
- Investigate: `MeasureMe/AppRuntimeConfigurator.swift:22,80-160`, `MeasureMe/DesignSystem/AppColorRoles.swift:5-11`, `MeasureMe/MeasureMeApp.swift:115`
- Modify (only if it reproduces): `MeasureMe/AppRuntimeConfigurator.swift`

- [ ] **Step 1: Build and install a debug build**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -scheme MeasureMe -configuration Debug \
  -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' \
  -derivedDataPath /tmp/mm-high-dd build
```

- [ ] **Step 2: Reproduce, both directions**

With the **simulator** in light appearance:
1. Launch the app, go to Settings → Experience → Appearance, choose **Dark**.
2. Navigate to any screen with a large navigation title and look at the nav bar background and title colour against the content.
3. Screenshot.

Then with the **simulator** in dark appearance, choose **Light** in the app and repeat.

Record what you see for each direction. The bug is present only if the bar chrome stays in the *system* appearance while the content switches.

- [ ] **Step 3a: If it does NOT reproduce — withdraw the finding**

Do not change code. Instead:

- Update the audit artifact (`https://claude.ai/code/artifact/cab1fc28-f090-448a-9de7-8784b915753d`) to remove the "UIKit chrome is configured once at launch and never re-themed" entry from High, and drop the High count from 7 to 6.
- Append a note to the `app-audit-2026-08` memory recording that the finding did not reproduce and why (`UIColor(dynamicProvider:)` resolves at draw time; `.preferredColorScheme` propagates to the window).
- Keep the two *other* problems in that same function, which are real and belong to their own findings: the fixed-size `UIFont.systemFont(ofSize:)` proxies (Medium — Dynamic Type) and `configureWithOpaqueBackground()` + `backgroundEffect = nil` opting out of iOS 26 glass (Low — iOS 26). Neither is in scope here.
- Commit only the memory change.

- [ ] **Step 3b: If it DOES reproduce — fix it at the SwiftUI layer**

Prefer driving the chrome from SwiftUI over re-running appearance proxies, because proxies only affect views created after the change, so re-running them still leaves already-mounted screens stale.

The legacy tab path in `TabBarContainer.swift` already demonstrates the pattern:

```swift
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarBackground(AppColorRoles.surfaceChrome, for: .tabBar)
```

Apply the equivalent for the navigation bar at the `NavigationStack` content root, and reduce `configureNavigationAppearance` to the parts SwiftUI cannot express (the rounded title fonts). Add the modifier once, in the shared scaffold rather than per screen — find it with:

```bash
/usr/bin/grep -rn --include='*.swift' 'NavigationStack' MeasureMe | head -20
```

- [ ] **Step 4: Re-verify**

Repeat Step 2 and confirm both directions now match. Then run the full suite and set-difference against the merge base per Global Constraints.

- [ ] **Step 5: Commit**

```bash
# if fixed
git add MeasureMe/AppRuntimeConfigurator.swift MeasureMe/TabBarContainer.swift
git commit -m "fix(theming): follow the in-app appearance override in navigation chrome"

# if withdrawn
git commit -m "docs: withdraw the UIKit chrome theming finding after it failed to reproduce"
```

---

## Closing out

After the last task:

- [ ] Run the full `MeasureMeTests` suite on the branch and at the merge base, and confirm the failing-set difference is empty in both directions.
- [ ] Update the audit artifact: mark the High section resolved (or 6 of 7, if Task 7 was withdrawn), the same way the Critical section will be marked.
- [ ] Add the decisions taken here to the `app-audit-2026-08` memory: diagnostics logging default flipped to off, insight cache moved out of the App Group, notification rescheduling scoped to the three recurring kinds.
