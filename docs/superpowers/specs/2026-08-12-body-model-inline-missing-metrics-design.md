# Uzupełnianie brakujących danych bez wychodzenia z modelu 3D

**Data:** 2026-08-12
**Status:** zatwierdzony design

## Problem

`BodyModelScreen` ma dwa stany blokujące, i oba wyrzucają użytkownika z ekranu:

- `.needsProfile` — brak płci w profilu. Karta zamyka ekran i przełącza na zakładkę Ustawienia.
- `.missingMetrics` — brakuje pomiarów. Karta wypisuje braki jako listę sklejoną przecinkami
  wewnątrz zdania, zamyka ekran i przełącza na zakładkę Measurements.

Użytkownik, który pierwszy raz otwiera model 3D, praktycznie zawsze trafia w jeden z tych stanów.
Traci kontekst, sam musi odtworzyć w pamięci listę braków, a po uzupełnieniu wrócić na ekran
modelu ręcznie.

## Cel

Na ekranie modelu 3D użytkownik widzi czytelną listę brakujących danych i uzupełnia je na miejscu.
Model przelicza się bez opuszczania ekranu.

## Zakres

Zmienia się wyłącznie obsługa dwóch stanów blokujących. Premium teaser, mannequin, picker dat,
suwak morfowania, quality note i lista zmian pozostają bez zmian.

## Architektura

### 1. `BodyModel/BodyModelMissingMetrics.swift` (nowy)

Czysta logika mapowania, bez SwiftUI — decyzja siedzi w funkcji, którą da się przetestować
bez instalowania widoku.

```swift
nonisolated enum BodyModelMissingMetrics {
    struct Row: Identifiable, Equatable {
        let id: String            // stabilny, niezlokalizowany — na nim asertują testy
        let title: String         // już zlokalizowany tytuł do wyświetlenia
        let systemImage: String
    }

    /// Etykiety do listy braków. Pary L/P zwinięte do neutralnej nazwy części ciała.
    static func rows(for kinds: [MetricKind]) -> [Row]

    /// Metryki do arkusza QuickAdd. Pary rozwinięte na obie strony.
    static func quickAddKinds(for kinds: [MetricKind]) -> [MetricKind]
}
```

Mapowanie par:

| Zgłoszone przez builder | `Row.id` | `Row.title` | Metryki w arkuszu |
| --- | --- | --- | --- |
| `.leftBicep` | `bodyModel.site.bicep` | `AppLocalization.string(BodyMeasurementSite.bicep.localizationKey)` | `.leftBicep`, `.rightBicep` |
| `.leftForearm` | `bodyModel.site.forearm` | j.w. dla `.forearm` | `.leftForearm`, `.rightForearm` |
| `.leftThigh` | `bodyModel.site.thigh` | j.w. dla `.thigh` | `.leftThigh`, `.rightThigh` |
| `.leftCalf` | `bodyModel.site.calf` | j.w. dla `.calf` | `.leftCalf`, `.rightCalf` |
| wszystko inne | `kind.rawValue` | `kind.title` | ta sama metryka |

`title` jest już zlokalizowany, więc testy asertują na `id` i `systemImage` — nie na tekst.
Dzięki temu mapowanie nie duplikuje kluczy lokalizacji dla metryk pojedynczych.

Rozwinięcie pary na obie strony jest zawsze bezpieczne: `BodySnapshotBuilder.build` zgłasza
`pair.left` tylko wtedy, gdy `pairValue` zwróci `nil`, co zachodzi wyłącznie gdy **obie** strony
są puste. Arkusz nigdy nie zaproponuje strony, która ma już zapisany pomiar.

Ikona wiersza pary pochodzi z lewej metryki (`kind.systemImage`) — obie strony mają ten sam symbol.

Kolejność wierszy jest kolejnością wejściowej tablicy, którą builder już sortuje wg
`MetricKind.allCases`.

### 2. `BodyModel/BodyModelSetupCards.swift` (nowy)

Dwie karty wydzielone z `BodyModelScreen`, który ma już 293 linie.

**`BodyModelGenderCard`** — tytuł, opis, segmented picker Kobieta / Mężczyzna. Przyjmuje
`Binding<String>` na `profile.userGender` i zapisuje surową wartość `Gender.rawValue`.
Opcja `notSpecified` nie jest oferowana — to jest dokładnie stan, z którego karta wyprowadza.

**`BodyModelMissingMetricsCard`** — tytuł, wiersze `Row` (ikona + nazwa), przycisk
„Uzupełnij pomiary" wywołujący domknięcie przekazane przez ekran. Lista wierszy zastępuje
dotychczasowe zdanie ze sklejoną przecinkami wyliczanką.

Obie karty zachowują dotychczasowe identyfikatory dostępności (`photos.bodyModel.needsProfile`,
`photos.bodyModel.missingMetrics`), żeby istniejące testy UI dalej celowały we właściwy element.

### 3. Zmiany w `BodyModelScreen.swift`

- `case .needsProfile` renderuje `BodyModelGenderCard` zamiast `EmptyStateCard` z nawigacją.
- `case .missingMetrics(kinds)` renderuje `BodyModelMissingMetricsCard` z
  `BodyModelMissingMetrics.rows(for: kinds)`; przycisk ustawia `@State isAddingMeasurements = true`.
- Nowy `.sheet(isPresented: $isAddingMeasurements)` z `QuickAddSheetView`.
- Nowy `@AppSetting(\.profile.unitsSystem)` — ekran dziś go nie czyta, a arkusz go wymaga.
- Nowy `.onChange(of: userGender) { _, _ in reload() }`.

Znikają `dismiss()` i `router.selectTab(...)` z obu ścieżek. To jedyne użycia
`@Environment(\.dismiss)` (linie 72, 88) i `@EnvironmentObject router` (linie 73, 89) w tym pliku,
więc obie właściwości stają się orphanami tej zmiany i lecą razem z nią.

### 4. Arkusz QuickAdd

```swift
QuickAddSheetView(
    kinds: BodyModelMissingMetrics.quickAddKinds(for: kinds),
    latest: latestByKind,
    unitsSystem: unitsSystem,
    telemetrySource: .bodyModel,
    onSaved: { isAddingMeasurements = false }
)
```

Reuse `QuickAddSheetView` daje klawiaturę numeryczną, przeliczanie jednostek, wspólną datę,
sanity-check, synchronizację HealthKit i zapis przez `QuickAddSaveService` bez pisania nowego kodu
wprowadzania.

`latest` budowane z `samples` (`@Query` już jest na ekranie): najnowsza próbka per metryka.
Metryka może być „brakująca" w oknie ±14 dni, a mimo to mieć starszy wpis — wtedy pole prefilluje
się starą wartością, dokładnie tak jak QuickAdd zachowuje się w całej aplikacji.

Metryki spoza `ActiveMetricsStore.activeKinds` są tu w porządku: `QuickAddSheetView` przyjmuje
jawną listę `kinds` (`HomeScreen` już z tego korzysta), a `QuickAddSaveService` zapisuje próbkę
niezależnie od tego, czy metryka jest aktywna.

### 5. Przeliczenie w miejscu

- Zapis pomiarów → `@Query samples` się aktualizuje → istniejące
  `.onChange(of: samples.count)` woła `reload()`.
- Wybór płci → zapis do `@AppSetting` nie woła `reload()` sam z siebie, stąd nowy
  `.onChange(of: userGender)`.

Jeśli po zapisie część metryk wciąż brakuje, karta renderuje się z krótszą listą. Pętla domyka się
sama, bez dodatkowego stanu.

### 6. Telemetria

Nowy przypadek w `MeasurementTelemetrySource` (`AnalyticsEvents.swift`):

```swift
case bodyModel = "body_model"
```

Pozwala odróżnić zapisy wykonane z ekranu modelu od zwykłego QuickAdd.

### 7. Lokalizacja

Zmiany w sześciu `.lproj` (en, pl, de, es, fr, pt-BR).

Nowe klucze:

- `bodyModel.empty.metrics.listTitle` — nagłówek nad listą braków (bez `%@`)
- `bodyModel.empty.profile.genderLabel` — etykieta pickera płci

Zachowane bez zmian: `bodyModel.empty.metrics.title`, `bodyModel.empty.profile.title`,
`bodyModel.empty.profile.message`. Przycisk arkusza używa istniejącego
`bodyModel.empty.metrics.action` („Add measurements") — nowy klucz nie jest potrzebny.

Do usunięcia, bo tracą jedyne użycie: `bodyModel.empty.metrics.message`
(format z `%@`, zastąpiony listą) i `bodyModel.empty.profile.action` („Open profile").

## Testy

**Unit — `BodyModelMissingMetricsTests` (nowy)**

- `rows(for:)` zwija `.leftBicep` do jednego wiersza z kluczem `bodyModel.site.bicep`
- `rows(for:)` zachowuje metryki pojedyncze 1:1 i kolejność wejścia
- `quickAddKinds(for:)` rozwija każdą parę na obie strony
- `quickAddKinds(for:)` nie duplikuje metryk pojedynczych

**Unit — `BodyModelViewModelTests` (rozszerzenie)**

- po dopisaniu brakującej metryki do zestawu próbek `load(...)` przechodzi z `.missingMetrics`
  w `.single`

**UI — `BodyModelUITests` (rozszerzenie)**

- w stanie `photos.bodyModel.needsProfile` picker płci istnieje i jest interaktywny

**Snapshot — `BodyModelSnapshotTests`**

- jeśli pokrywa stany blokujące, baseline'y wymagają regeneracji

## Poza zakresem

- pasek postępu typu „4 z 18"
- edycja wieku i wzrostu w profilu z tego ekranu (wzrost i tak jest metryką i wejdzie przez arkusz,
  gdy `manualHeight` jest nieustawiony)
- uzupełnianie braków, gdy model już się renderuje — `.missingMetrics` wtedy nie występuje
