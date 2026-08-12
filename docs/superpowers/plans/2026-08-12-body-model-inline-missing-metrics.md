# Body Model — Inline Missing-Data Entry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Na ekranie modelu 3D użytkownik widzi listę brakujących danych i uzupełnia je na miejscu, bez opuszczania ekranu.

**Architecture:** Czysta funkcja mapująca braki zgłoszone przez `BodySnapshotBuilder` na wiersze listy i na metryki do arkusza (pary L/P zwijane w liście, rozwijane w arkuszu). Dwie karty prezentacyjne w osobnym pliku. `BodyModelScreen` podmienia obie karty stanów blokujących i prezentuje istniejący `QuickAddSheetView` jako `.sheet`, zamiast zamykać ekran i przełączać zakładkę.

**Tech Stack:** Swift 6.4, SwiftUI, SwiftData, XCTest. Xcode 27.0 beta.

**Spec:** [`docs/superpowers/specs/2026-08-12-body-model-inline-missing-metrics-design.md`](../specs/2026-08-12-body-model-inline-missing-metrics-design.md)

## Global Constraints

- Projekt ustawia `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` dla targetu `MeasureMe`. `AppLocalization.string` i `MetricKind.title` są przez to izolowane do `@MainActor` — nowy typ `BodyModelMissingMetrics` **nie** może być `nonisolated`, a jego testy muszą być `@MainActor`.
- `xcodebuild` nie jest na domyślnym toolchainie. **Każde** polecenie build/test poprzedź:
  `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`
- Symulator do testów: iPhone 17 Pro, iOS 27.0, udid `423D83EE-E5BE-42DC-A5F8-0B3EB62A0182`.
- `-only-testing` z nieistniejącą nazwą klasy dopasowuje zero testów i **i tak** raportuje `** TEST SUCCEEDED **`. Po każdym uruchomieniu sprawdź linię `Executed N tests` i porównaj z oczekiwaną liczbą. Zielony przebieg sam w sobie niczego nie dowodzi.
- 20 istniejących testów snapshotowych pada na iOS 27 z powodu nieaktualnych baseline'ów (nie regresji). Nie dotykaj ich; `BodyModelSnapshotTests` nie jest objęty tą zmianą.
- Komentarze i nazwy po angielsku, docstringi testów po polsku — tak jak w `BodyModelViewModelTests.swift` i `BodyModelUITests.swift`.
- Nie usuwaj zastanego martwego kodu spoza zakresu. Usuwaj wyłącznie orphany, które tworzy ta zmiana (wyliczone imiennie w Task 4).
- Sześć języków: `en`, `pl`, `de`, `es`, `fr`, `pt-BR`. Każdy klucz musi istnieć we wszystkich sześciu — pilnuje tego `LocalizationConsistencyTests`.

---

### Task 1: `BodyModelMissingMetrics` — mapowanie braków

**Files:**
- Create: `MeasureMe/BodyModel/BodyModelMissingMetrics.swift`
- Test: `MeasureMeTests/BodyModelMissingMetricsTests.swift`

**Interfaces:**
- Consumes: `MetricKind` (`.rawValue`, `.title`, `.systemImage`), `BodyMeasurementSite.localizationKey`, `AppLocalization.string(_:)` — wszystkie istnieją.
- Produces:
  - `BodyModelMissingMetrics.Row` — `struct Row: Identifiable, Equatable { let id: String; let title: String; let systemImage: String }`
  - `static func rows(for kinds: [MetricKind]) -> [Row]`
  - `static func quickAddKinds(for kinds: [MetricKind]) -> [MetricKind]`
  - Task 3 i 4 używają obu funkcji i pola `Row.id` / `Row.title` / `Row.systemImage`.

**Kontekst dla implementującego:** `BodySnapshotBuilder.build` (`MeasureMe/BodyModel/BodySnapshotBuilder.swift:99`) zgłasza jako brakującą tylko lewą stronę pary (`pairs[i].left`) i robi to wyłącznie wtedy, gdy `pairValue` zwróci `nil` — a to zachodzi tylko gdy **obie** strony są puste. Dlatego rozwinięcie `.leftBicep` na `[.leftBicep, .rightBicep]` nigdy nie zaproponuje strony, która ma już zapisany pomiar.

- [ ] **Step 1: Write the failing test**

Utwórz `MeasureMeTests/BodyModelMissingMetricsTests.swift`:

```swift
/// Cel testow: Sprawdza mapowanie brakujacych metryk na wiersze listy i na metryki arkusza QuickAdd.
/// Dlaczego to wazne: Builder zglasza tylko lewa strone pary; ekran musi pokazac neutralna nazwe,
///   a arkusz zaoferowac obie strony.
/// Kryteria zaliczenia: Pary zwijaja sie w liscie i rozwijaja w arkuszu, metryki pojedyncze przechodza 1:1.

import XCTest
@testable import MeasureMe

@MainActor
final class BodyModelMissingMetricsTests: XCTestCase {

    /// Co sprawdza: Lewa strona pary daje jeden wiersz z neutralnym identyfikatorem czesci ciala.
    /// Dlaczego: Model usrednia lewa i prawa, wiec nazwanie strony twierdziloby cos, czego model nie widzial.
    /// Kryteria: Dla .leftBicep powstaje dokladnie jeden wiersz o id "bodyModel.site.bicep".
    func testPairCollapsesToNeutralRow() {
        let rows = BodyModelMissingMetrics.rows(for: [.leftBicep])

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, "bodyModel.site.bicep")
        XCTAssertEqual(rows.first?.systemImage, MetricKind.leftBicep.systemImage)
    }

    /// Co sprawdza: Wszystkie cztery pary zwijaja sie do neutralnych nazw.
    /// Dlaczego: Regresja na jednej parze byla latwa do przeoczenia przy tescie tylko bicepsa.
    /// Kryteria: Cztery lewe strony daja cztery wiersze o kluczach BodyMeasurementSite.
    func testEveryPairCollapses() {
        let rows = BodyModelMissingMetrics.rows(for: [.leftBicep, .leftForearm, .leftThigh, .leftCalf])

        XCTAssertEqual(rows.map(\.id), [
            "bodyModel.site.bicep",
            "bodyModel.site.forearm",
            "bodyModel.site.thigh",
            "bodyModel.site.calf"
        ])
    }

    /// Co sprawdza: Metryki pojedyncze przechodza bez zmian i zachowuja kolejnosc wejscia.
    /// Dlaczego: Builder sortuje braki wg MetricKind.allCases i ta kolejnosc ma dotrzec do UI.
    /// Kryteria: id to rawValue metryki, kolejnosc zgodna z wejsciem.
    func testSingleKindsPassThroughInOrder() {
        let rows = BodyModelMissingMetrics.rows(for: [.height, .weight, .neck])

        XCTAssertEqual(rows.map(\.id), [
            MetricKind.height.rawValue,
            MetricKind.weight.rawValue,
            MetricKind.neck.rawValue
        ])
    }

    /// Co sprawdza: Wiersz ma niepusty tytul rozny od wlasnego id.
    /// Dlaczego: AppLocalization.string zwraca klucz, gdy tlumaczenia brakuje — to by przeciekło do UI.
    /// Kryteria: Tytul jest niepusty i nie jest surowym kluczem.
    func testRowTitleIsLocalizedNotARawKey() {
        let rows = BodyModelMissingMetrics.rows(for: [.leftBicep, .neck])

        for row in rows {
            XCTAssertFalse(row.title.isEmpty, "Row \(row.id) has an empty title")
            XCTAssertNotEqual(row.title, row.id, "Row \(row.id) leaked its key as the title")
        }
    }

    /// Co sprawdza: Arkusz QuickAdd dostaje obie strony kazdej pary.
    /// Dlaczego: Builder zglasza lewa strone tylko wtedy, gdy obie sa puste, wiec obie mozna zaoferowac.
    /// Kryteria: .leftThigh rozwija sie do [.leftThigh, .rightThigh].
    func testQuickAddKindsExpandPairs() {
        let kinds = BodyModelMissingMetrics.quickAddKinds(for: [.leftThigh])

        XCTAssertEqual(kinds, [.leftThigh, .rightThigh])
    }

    /// Co sprawdza: Metryki pojedyncze nie sa duplikowane przy rozwijaniu.
    /// Dlaczego: Blad w flatMap latwo podwaja wszystko, nie tylko pary.
    /// Kryteria: Mieszane wejscie daje dokladnie oczekiwana liste.
    func testQuickAddKindsLeaveSingleKindsAlone() {
        let kinds = BodyModelMissingMetrics.quickAddKinds(for: [.waist, .leftCalf, .hips])

        XCTAssertEqual(kinds, [.waist, .leftCalf, .rightCalf, .hips])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/BodyModelMissingMetricsTests
```

Expected: kompilacja pada z `cannot find 'BodyModelMissingMetrics' in scope`.

- [ ] **Step 3: Write the implementation**

Utwórz `MeasureMe/BodyModel/BodyModelMissingMetrics.swift`:

```swift
// BodyModelMissingMetrics.swift
//
// **BodyModelMissingMetrics**
// Turns the metrics `BodySnapshotBuilder` reports as missing into something the
// screen can show and something `QuickAddSheetView` can accept.
//
// **Why the two lists differ:**
// The builder reports only the left side of a pair, and only when both sides are
// empty. Naming a side in the list would claim the model cared about one arm; but
// once the user is typing, offering both sides is what the rest of the app does.
// So the list collapses a pair to a neutral body-part name and the sheet expands
// it back to left and right.
//
// Not `nonisolated`: `Row.title` resolves through `AppLocalization` and
// `MetricKind.title`, both of which are MainActor-isolated in this target.
//
import Foundation

enum BodyModelMissingMetrics {

    /// One entry in the list of what the user still has to log.
    struct Row: Identifiable, Equatable {
        /// Stable and unlocalized, so tests and `ForEach` never depend on the display language.
        let id: String
        let title: String
        let systemImage: String
    }

    /// Left side of each pair → the neutral site it collapses to, and the right side it expands back to.
    private static let pairs: [MetricKind: (site: BodyMeasurementSite, right: MetricKind)] = [
        .leftBicep: (.bicep, .rightBicep),
        .leftForearm: (.forearm, .rightForearm),
        .leftThigh: (.thigh, .rightThigh),
        .leftCalf: (.calf, .rightCalf)
    ]

    /// List rows, in the order the builder reported them (already `MetricKind.allCases` order).
    static func rows(for kinds: [MetricKind]) -> [Row] {
        kinds.map { kind in
            guard let pair = pairs[kind] else {
                return Row(id: kind.rawValue, title: kind.title, systemImage: kind.systemImage)
            }
            return Row(
                id: pair.site.localizationKey,
                title: AppLocalization.string(pair.site.localizationKey),
                systemImage: kind.systemImage
            )
        }
    }

    /// Metrics to hand `QuickAddSheetView`, with both sides of every pair.
    static func quickAddKinds(for kinds: [MetricKind]) -> [MetricKind] {
        kinds.flatMap { kind -> [MetricKind] in
            guard let pair = pairs[kind] else { return [kind] }
            return [kind, pair.right]
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/BodyModelMissingMetricsTests
```

Expected: `** TEST SUCCEEDED **` oraz `Executed 6 tests, with 0 failures`. Jeśli linia mówi `Executed 0 tests`, klasa nie została znaleziona — sprawdź, czy plik trafił do targetu `MeasureMeTests`.

- [ ] **Step 5: Commit**

```bash
git add MeasureMe/BodyModel/BodyModelMissingMetrics.swift MeasureMeTests/BodyModelMissingMetricsTests.swift
git commit -m "feat(body-model): map missing metrics to list rows and quick-add kinds"
```

---

### Task 2: Słownik — przypadek telemetrii i nowe klucze lokalizacji

**Files:**
- Modify: `MeasureMe/AnalyticsEvents.swift:114-121`
- Modify: `MeasureMe/en.lproj/Localizable.strings`
- Modify: `MeasureMe/pl.lproj/Localizable.strings`
- Modify: `MeasureMe/de.lproj/Localizable.strings`
- Modify: `MeasureMe/es.lproj/Localizable.strings`
- Modify: `MeasureMe/fr.lproj/Localizable.strings`
- Modify: `MeasureMe/pt-BR.lproj/Localizable.strings`

**Interfaces:**
- Produces:
  - `MeasurementTelemetrySource.bodyModel` (rawValue `"body_model"`) — Task 4 przekazuje go do `QuickAddSheetView`.
  - Klucze `bodyModel.empty.metrics.listTitle` i `bodyModel.empty.profile.genderLabel` — Task 3 je czyta.

**Kontekst:** Klucze `bodyModel.*` żyją koło linii 2118 w `en.lproj` i 2071 w `pl.lproj`. Wstaw nowe obok istniejących `bodyModel.empty.*`, żeby plik został pogrupowany. Usuwaniem martwych kluczy zajmuje się Task 4 — tutaj tylko dodajesz.

- [ ] **Step 1: Add the telemetry case**

W `MeasureMe/AnalyticsEvents.swift` dopisz przypadek do `MeasurementTelemetrySource`, po `intent`:

```swift
nonisolated enum MeasurementTelemetrySource: String {
    case onboarding
    case activation
    case quickAdd = "quick_add"
    case widget
    case watch
    case intent
    case bodyModel = "body_model"
}
```

- [ ] **Step 2: Add the two keys to every language**

Dopisz obok istniejącego bloku `bodyModel.empty.*` w każdym pliku:

`en.lproj`:
```
"bodyModel.empty.metrics.listTitle" = "Still to log";
"bodyModel.empty.profile.genderLabel" = "Sex";
```

`pl.lproj`:
```
"bodyModel.empty.metrics.listTitle" = "Do uzupełnienia";
"bodyModel.empty.profile.genderLabel" = "Płeć";
```

`de.lproj`:
```
"bodyModel.empty.metrics.listTitle" = "Noch zu erfassen";
"bodyModel.empty.profile.genderLabel" = "Geschlecht";
```

`es.lproj`:
```
"bodyModel.empty.metrics.listTitle" = "Aún por registrar";
"bodyModel.empty.profile.genderLabel" = "Sexo";
```

`fr.lproj`:
```
"bodyModel.empty.metrics.listTitle" = "Encore à saisir";
"bodyModel.empty.profile.genderLabel" = "Sexe";
```

`pt-BR.lproj`:
```
"bodyModel.empty.metrics.listTitle" = "Ainda a registrar";
"bodyModel.empty.profile.genderLabel" = "Sexo";
```

- [ ] **Step 3: Run the localization tests**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/LocalizationConsistencyTests
```

Expected: `Executed 5 tests, with 0 failures`. Ta klasa sprawdza równość zbiorów kluczy między językami, puste wartości, zgodność argumentów formatu i duplikaty — jeśli pominąłeś któryś język albo zrobiłeś literówkę w kluczu, tu to wyjdzie.

- [ ] **Step 4: Commit**

```bash
git add MeasureMe/AnalyticsEvents.swift MeasureMe/*.lproj/Localizable.strings
git commit -m "feat(body-model): add body_model telemetry source and inline-entry strings"
```

---

### Task 3: Karty `BodyModelSetupCards.swift`

**Files:**
- Create: `MeasureMe/BodyModel/BodyModelSetupCards.swift`

**Interfaces:**
- Consumes: `BodyModelMissingMetrics.Row` (Task 1), klucze `bodyModel.empty.metrics.listTitle` i `bodyModel.empty.profile.genderLabel` (Task 2), `AppGlassCard`, `AppSpacing`, `AppRadius`, `AppTypography`, `AppColorRoles`, `AppCTAButtonStyle`, `FeatureTheme.photos`, `Gender`.
- Produces:
  - `BodyModelGenderCard(selectedGender: Binding<String>)`
  - `BodyModelMissingMetricsCard(rows: [BodyModelMissingMetrics.Row], onAdd: () -> Void)`
  - Task 4 tworzy oba widoki.

**Kontekst dla implementującego:** Nie używaj `EmptyStateCard`. Ma on `.accessibilityElement(children: .combine)` (`MeasureMe/DesignSystem/AppStateComponents.swift:39`), co scala całą zawartość w jeden element — picker płci i przycisk przestałyby być osobno dostępne dla VoiceOver i dla XCUITest. Te karty budują na `AppGlassCard` bezpośrednio.

Identyfikatory dostępności `photos.bodyModel.needsProfile` i `photos.bodyModel.missingMetrics` **muszą zostać zachowane** — `BodyModelUITests.testOpeningBodyModelWithUiTestModeShowsRealScreen` (linia 71) celuje w pierwszy z nich.

- [ ] **Step 1: Write the file**

```swift
// BodyModelSetupCards.swift
//
// **BodyModelGenderCard / BodyModelMissingMetricsCard**
// The two cards that stand between a new user and their first silhouette.
//
// **Why not EmptyStateCard:**
// That card combines its children into a single accessibility element, which is
// right for a title-message-button trio and wrong here: the sex picker and the
// list of what is missing have to stay individually reachable.
//
import SwiftUI

/// Lets the user set their sex without leaving the body model screen.
struct BodyModelGenderCard: View {
    @Binding var selectedGender: String

    private let theme = FeatureTheme.photos

    var body: some View {
        AppGlassCard(depth: .elevated, cornerRadius: AppRadius.xl, tint: theme.softTint) {
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)

                Text(AppLocalization.string("bodyModel.empty.profile.title"))
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColorRoles.textPrimary)
                    .multilineTextAlignment(.center)

                Text(AppLocalization.string("bodyModel.empty.profile.message"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColorRoles.textSecondary)
                    .multilineTextAlignment(.center)

                Picker(
                    AppLocalization.string("bodyModel.empty.profile.genderLabel"),
                    selection: $selectedGender
                ) {
                    Text(Gender.female.displayName).tag(Gender.female.rawValue)
                    Text(Gender.male.displayName).tag(Gender.male.rawValue)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("photos.bodyModel.genderPicker")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.xs)
        }
        .accessibilityIdentifier("photos.bodyModel.needsProfile")
    }
}

/// Lists what the user still has to log, and opens the sheet that logs it.
struct BodyModelMissingMetricsCard: View {
    let rows: [BodyModelMissingMetrics.Row]
    let onAdd: () -> Void

    private let theme = FeatureTheme.photos

    var body: some View {
        AppGlassCard(depth: .elevated, cornerRadius: AppRadius.xl, tint: theme.softTint) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(AppLocalization.string("bodyModel.empty.metrics.title"))
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColorRoles.textPrimary)

                Text(AppLocalization.string("bodyModel.empty.metrics.listTitle"))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(AppColorRoles.textSecondary)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    ForEach(rows) { row in
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: row.systemImage)
                                .font(AppTypography.iconSmall)
                                .foregroundStyle(theme.accent)
                                .frame(width: 24)
                                .accessibilityHidden(true)

                            Text(row.title)
                                .font(AppTypography.body)
                                .foregroundStyle(AppColorRoles.textPrimary)
                        }
                    }
                }

                Button(AppLocalization.string("bodyModel.empty.metrics.action"), action: onAdd)
                    .buttonStyle(AppCTAButtonStyle(size: .compact, cornerRadius: AppRadius.md))
                    .appHitTarget()
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("photos.bodyModel.addMissing")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, AppSpacing.xs)
        }
        .accessibilityIdentifier("photos.bodyModel.missingMetrics")
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcodebuild build -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182'
```

Expected: `** BUILD SUCCEEDED **`.

Jeśli któryś token nie istnieje pod użytą nazwą (`AppTypography.iconSmall`, `AppCTAButtonStyle(size:cornerRadius:)`, `.appHitTarget()`), sprawdź faktyczną nazwę w `MeasureMe/DesignSystem/` i `MeasureMe/AppButtonStyles.swift` i użyj jej — nie dopisuj nowych tokenów.

- [ ] **Step 3: Commit**

```bash
git add MeasureMe/BodyModel/BodyModelSetupCards.swift
git commit -m "feat(body-model): cards for sex selection and the missing-metric list"
```

---

### Task 4: Podpięcie do `BodyModelScreen`

**Files:**
- Modify: `MeasureMe/BodyModel/BodyModelScreen.swift` (linie 21, 28-31, 58-59, 65-92)
- Modify: `MeasureMe/en.lproj/Localizable.strings` (usunięcie 2 kluczy)
- Modify: `MeasureMe/pl.lproj/Localizable.strings` (usunięcie 2 kluczy)
- Modify: `MeasureMe/de.lproj/Localizable.strings` (usunięcie 2 kluczy)
- Modify: `MeasureMe/es.lproj/Localizable.strings` (usunięcie 2 kluczy)
- Modify: `MeasureMe/fr.lproj/Localizable.strings` (usunięcie 2 kluczy)
- Modify: `MeasureMe/pt-BR.lproj/Localizable.strings` (usunięcie 2 kluczy)
- Test: `MeasureMeTests/BodyModelViewModelTests.swift` (dopisanie jednego testu)

**Interfaces:**
- Consumes: `BodyModelMissingMetrics.rows(for:)` i `.quickAddKinds(for:)` (Task 1), `MeasurementTelemetrySource.bodyModel` (Task 2), `BodyModelGenderCard` i `BodyModelMissingMetricsCard` (Task 3), istniejące `QuickAddSheetView(kinds:latest:unitsSystem:telemetrySource:customDefinitions:customLatest:onSaved:)`.
- Produces: nic dla późniejszych zadań.

**Kontekst dla implementującego:** `QuickAddSheetView` przyjmuje jawną listę `kinds`, więc metryki spoza `ActiveMetricsStore.activeKinds` są w porządku — `HomeScreen.swift:494` już z tego korzysta. Zapis idzie przez `QuickAddSaveService` niezależnie od tego, czy metryka jest aktywna.

`latest` buduje się z `samples`, które ekran ma już przez `@Query` (linia 28), posortowane malejąco po dacie — więc pierwsze trafienie danego rodzaju jest najnowsze.

- [ ] **Step 1: Write the failing test for the state transition**

Dopisz na końcu klasy w `MeasureMeTests/BodyModelViewModelTests.swift`, przed zamykającym `}`:

```swift
    /// Co sprawdza: Dopisanie brakujacej metryki przeprowadza stan z .missingMetrics w .single.
    /// Dlaczego: Na tym stoi uzupelnianie w miejscu — po zapisie ekran ma sam przeliczyc model,
    ///   bez zamykania i ponownego otwierania.
    /// Kryteria: Ten sam view model po ponownym load() z kompletem probek jest w stanie .single.
    func testLoggingTheMissingMetricAdvancesToSingle() {
        let incomplete = completeSamples(at: anchor).filter { $0.kindRaw != MetricKind.neck.rawValue }
        let viewModel = BodyModelViewModel()
        viewModel.load(samples: incomplete, gender: .male, age: 30, fallbackHeightCm: 180)

        guard case .missingMetrics = viewModel.state else {
            return XCTFail("Precondition: expected missingMetrics, got \(viewModel.state)")
        }

        let completed = incomplete + [MetricSample(kind: .neck, value: 38, date: anchor)]
        viewModel.load(samples: completed, gender: .male, age: 30, fallbackHeightCm: 180)

        guard case .single = viewModel.state else {
            return XCTFail("Expected single after logging the missing metric, got \(viewModel.state)")
        }
    }
```

- [ ] **Step 2: Run it — this one is expected to PASS**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/BodyModelViewModelTests
```

Expected: `Executed 9 tests, with 0 failures` (8 istniejących plus nowy — baseline na tej gałęzi zmierzono: 8).

To jest test charakteryzujący, nie czerwony-zielony: `BodyModelViewModel.load` już umie to przejście, a ta zmiana polega na tym, że ekran je w ogóle wywoła. Test przypina zachowanie, na którym stoi cała funkcja, żeby przyszła zmiana w `load` nie rozbiła jej po cichu. Jeśli **padnie**, przerwij i zgłoś — założenie planu jest wtedy fałszywe.

- [ ] **Step 3: Add the sheet-request wrapper**

`.sheet(item:)` wymaga `Identifiable`, a `[MetricKind]` nim nie jest. Alternatywa — `isPresented` plus osobne `@State` na listę metryk — trzymałaby dwa źródła prawdy dla jednej prezentacji. Dopisz na dole `MeasureMe/BodyModel/BodyModelScreen.swift`, **poza** `struct BodyModelScreen`:

```swift
/// Wrapper so the quick-add sheet can be driven by `.sheet(item:)` — the metrics
/// it offers change per presentation, so a plain `isPresented` flag would need a
/// second source of truth for "which ones".
private struct QuickAddRequest: Identifiable {
    let id = UUID()
    let kinds: [MetricKind]
}
```

- [ ] **Step 4: Add the state, the setting and the prefill source**

Dopisz do właściwości widoku (koło linii 30, obok `@State private var rotationRadians`):

```swift
    @AppSetting(\.profile.unitsSystem) private var unitsSystem: String = "metric"
    /// Non-nil while the quick-add sheet is up; carries the metrics it should offer.
    @State private var quickAddRequest: QuickAddRequest?
```

Dopisz computed property obok `resolvedGender`:

```swift
    /// Newest sample per kind, for prefilling the quick-add sheet. `samples` is already
    /// sorted newest-first, so the first hit for a kind wins.
    private var latestByKind: [MetricKind: (value: Double, date: Date)] {
        var result: [MetricKind: (value: Double, date: Date)] = [:]
        for sample in samples {
            guard let kind = MetricKind(rawValue: sample.kindRaw), result[kind] == nil else { continue }
            result[kind] = (sample.value, sample.date)
        }
        return result
    }
```

- [ ] **Step 5: Rewrite the two blocking states**

Zastąp obie gałęzie w `content` (linie 65-92) — cały blok od `case .needsProfile:` do zamknięcia `EmptyStateCard` przy `case let .missingMetrics(kinds):`:

```swift
        case .needsProfile:
            BodyModelGenderCard(selectedGender: $userGender)

        case let .missingMetrics(kinds):
            BodyModelMissingMetricsCard(
                rows: BodyModelMissingMetrics.rows(for: kinds),
                onAdd: {
                    quickAddRequest = QuickAddRequest(
                        kinds: BodyModelMissingMetrics.quickAddKinds(for: kinds)
                    )
                }
            )
```

- [ ] **Step 6: Wire the sheet and the gender reload**

Zastąp modyfikatory na `NavigationStack` (linie 58-59):

```swift
        .onAppear(perform: reload)
        .onChange(of: samples.count) { _, _ in reload() }
        .onChange(of: userGender) { _, _ in reload() }
        .sheet(item: $quickAddRequest) { request in
            QuickAddSheetView(
                kinds: request.kinds,
                latest: latestByKind,
                unitsSystem: unitsSystem,
                telemetrySource: .bodyModel,
                onSaved: { quickAddRequest = nil }
            )
        }
```

`onChange(of: userGender)` jest konieczny, bo zapis do `@AppSetting` przerysowuje widok, ale sam z siebie nie woła `reload()` — bez niego wybór płci nie odblokowałby ekranu do następnego `onAppear`.

- [ ] **Step 7: Remove the orphans this change created**

Usuń z `BodyModelScreen.swift`:

```swift
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
```

To były ich jedyne użycia w tym pliku (linie 72-73 i 88-89 przed zmianą — `dismiss()` + `router.selectTab(...)` w obu kartach). Jeśli kompilator zgłosi, że któraś jest jednak nadal używana, zostaw ją i odnotuj to w commicie.

Usuń z **każdego** z sześciu `Localizable.strings` dwa klucze, które straciły jedyne użycie:

```
"bodyModel.empty.metrics.message"
"bodyModel.empty.profile.action"
```

Zostają bez zmian: `bodyModel.empty.metrics.title`, `bodyModel.empty.metrics.action`, `bodyModel.empty.profile.title`, `bodyModel.empty.profile.message`.

- [ ] **Step 8: Verify — build, unit tests, localization**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeTests/BodyModelViewModelTests -only-testing:MeasureMeTests/BodyModelMissingMetricsTests -only-testing:MeasureMeTests/LocalizationConsistencyTests
```

Expected: `** TEST SUCCEEDED **`, `Executed 20 tests, with 0 failures` (9 + 6 + 5).

Potwierdź też, że żaden kod nie odwołuje się do usuniętych kluczy:

```bash
rg -n "bodyModel.empty.metrics.message|bodyModel.empty.profile.action" MeasureMe/ MeasureMeTests/ MeasureMeUITests/
```

Expected: zero trafień.

- [ ] **Step 9: Commit**

```bash
git add MeasureMe/BodyModel/BodyModelScreen.swift MeasureMe/*.lproj/Localizable.strings MeasureMeTests/BodyModelViewModelTests.swift
git commit -m "feat(body-model): fill in missing data without leaving the screen"
```

---

### Task 5: Test UI i weryfikacja na symulatorze

**Files:**
- Modify: `MeasureMeUITests/BodyModelUITests.swift`

**Interfaces:**
- Consumes: identyfikator `photos.bodyModel.genderPicker` (Task 3), argument uruchomieniowy `-uiTestGenderNotSpecified` (istnieje, użyty w linii 58).

**Kontekst dla implementującego:** Test **nie może** tapać przycisku „Dodaj pomiary" ani segmentu pickera. W tym projekcie przyciski wewnątrz zawartości ignorują syntetyzowane tapnięcia XCUITest (to samo ograniczenie udokumentowano dla onboardingu). Test stwierdza obecność i możliwość trafienia, nie przeprowadza interakcji.

Nie uruchamiaj pełnego `MeasureMeUITests` — to 101 testów i 60-70 minut, a pierwszy przebieg na świeżo wyczyszczonym symulatorze i tak zwraca fałszywe porażki.

- [ ] **Step 1: Write the failing test**

Dopisz do `MeasureMeUITests/BodyModelUITests.swift`, przed `// MARK: - Helpers`:

```swift
    /// Co sprawdza: W stanie needsProfile ekran oferuje wybor plci na miejscu, zamiast odsylac do Ustawien.
    /// Dlaczego: To jest cala zmiana — user nie ma opuszczac ekranu modelu, zeby go odblokowac.
    /// Kryteria: Picker "photos.bodyModel.genderPicker" istnieje i jest trafialny.
    @MainActor
    func testNeedsProfileOffersGenderPickerInPlace() {
        app.launchArguments = ["-uiTestMode", "-uiTestGenderNotSpecified"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        tapTab(named: "tab.photos")

        let openButton = app.descendants(matching: .any)["photos.bodyModel.open"].firstMatch
        XCTAssertTrue(openButton.waitForExistence(timeout: 10), "Expected body model entry button on Photos tab.")
        openButton.tap()

        let picker = app.descendants(matching: .any)["photos.bodyModel.genderPicker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "Expected the sex picker inside the needsProfile card.")
        XCTAssertTrue(picker.isHittable, "The sex picker must be reachable, not buried in a combined element.")
    }
```

- [ ] **Step 2: Run the body model UI tests**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && xcodebuild test -scheme MeasureMe -destination 'platform=iOS Simulator,id=423D83EE-E5BE-42DC-A5F8-0B3EB62A0182' -only-testing:MeasureMeUITests/BodyModelUITests
```

Expected: `Executed 3 tests, with 0 failures` — dwa istniejące plus nowy. Jeśli padnie tylko nowy z powodu `isHittable`, przyczyną jest scalanie elementów dostępności; sprawdź, czy karta z Task 3 nie odziedziczyła `.accessibilityElement(children: .combine)`.

Jeśli padnie któryś z dwóch istniejących, to regresja z Task 4 — nie idź dalej.

- [ ] **Step 3: Check the flow by hand on the simulator**

Odpal aplikację i przejdź ścieżkę, której testy nie pokrywają (bo tapnięcia w zawartość nie działają):

1. Photos → otwórz model 3D
2. wybierz płeć → karta ma się zmienić na listę brakujących pomiarów, bez zamykania ekranu
3. „Dodaj pomiary" → arkusz zawiera **tylko** brakujące metryki, a pary mają wiersz lewy i prawy
4. zapisz → arkusz się zamyka, ekran przelicza się w miejscu; jeśli coś jeszcze brakuje, lista jest krótsza

Zrób zrzut ekranu kroków 2 i 3 i dołącz go do raportu z zadania.

- [ ] **Step 4: Commit**

```bash
git add MeasureMeUITests/BodyModelUITests.swift
git commit -m "test(body-model): assert the sex picker is reachable in place"
```

---

## Self-Review

**Pokrycie speca:**

| Sekcja speca | Zadanie |
| --- | --- |
| 1. `BodyModelMissingMetrics` | Task 1 |
| 2. `BodyModelSetupCards` | Task 3 |
| 3. Zmiany w `BodyModelScreen` | Task 4 |
| 4. Arkusz QuickAdd | Task 4 (Steps 3-6) |
| 5. Przeliczenie w miejscu | Task 4 (Step 6, `onChange(of: userGender)`) |
| 6. Telemetria | Task 2 (Step 1) |
| 7. Lokalizacja — dodanie | Task 2 (Step 2) |
| 7. Lokalizacja — usunięcie | Task 4 (Step 7) |
| Testy: unit mapowania | Task 1 |
| Testy: przejście stanu | Task 4 (Step 1) |
| Testy: UI pickera płci | Task 5 |
| Testy: snapshot | brak zadania — `BodyModelSnapshotTests` pokrywa tylko stan `comparison`, żaden baseline nie dotyka stanów blokujących |

**Odchylenie od speca:** spec opisywał `@State private var quickAddKinds: [MetricKind]?` sterowany przez `isPresented`; plan używa `.sheet(item:)` z opakowaniem `QuickAddRequest`, bo tablica nie jest `Identifiable`, a flaga `isPresented` wymagałaby drugiego źródła prawdy dla „które metryki". Zachowanie identyczne.

**Kolejność usuwania kluczy:** klucze `bodyModel.empty.metrics.message` i `bodyModel.empty.profile.action` znikają w Task 4, nie w Task 2 — do końca Task 3 wciąż używa ich stary kod `BodyModelScreen`. Usunięcie ich wcześniej zostawiłoby zielony build z surowym kluczem na ekranie.

**Spójność nazw:** `BodyModelMissingMetrics.rows(for:)` / `.quickAddKinds(for:)` i pola `Row.id` / `.title` / `.systemImage` użyte w Task 3 i 4 zgadzają się z definicją z Task 1. `BodyModelGenderCard(selectedGender:)` i `BodyModelMissingMetricsCard(rows:onAdd:)` z Task 3 zgadzają się z wywołaniami w Task 4. `MeasurementTelemetrySource.bodyModel` z Task 2 zgadza się z użyciem w Task 4.
