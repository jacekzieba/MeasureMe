# MeasureMe – dokumentacja aplikacji (Notion-ready)

Ostatnia aktualizacja: 2026-02-19  
Repo: `/Users/jacek/Desktop/MeasureMe`  

> Ten dokument jest pisany pod import do Notion (Markdown z naglowkami `# / ## / ###`).
> Opis bazuje na aktualnym stanie kodu i plikow w repo (SwiftUI/SwiftData, testy, CI).

---

## Spis tresci

1. Cel i zakres
2. Produkt i funkcje
3. Wymagania platformowe
4. Architektura (high-level)
5. Dane i persystencja (SwiftData)
6. Kluczowe moduly i przeplywy
7. Integracje systemowe (HealthKit, notyfikacje, Photos/Camera)
8. Obrazy i cache (pipeline)
9. Diagnostyka i crash reporting
10. Prywatnosc i bezpieczenstwo
11. Testy (unit, snapshot, UI)
12. CI (GitHub Actions)
13. Developer workflow (build/run/lint)
14. Zaleznosci
15. Konfiguracja (UserDefaults/AppStorage)
16. Ograniczenia i znane ryzyka
17. Zalaczniki (mapa plikow, komendy)

---

# 1. Cel i zakres

**MeasureMe** to aplikacja iOS do:
- sledzenia pomiarow ciala (metryki),
- robienia zdjec progresu i porownan,
- sledzenia trendow i celow,
- opcjonalnej synchronizacji z Apple Health (HealthKit),
- przypomnien (UserNotifications),
- funkcji premium (StoreKit 2), w tym AI Insights na urzadzeniach z Apple Intelligence.

Dokument opisuje:
- architekture i organizacje kodu,
- model danych i persystencje,
- kluczowe przeplywy uzytkownika,
- integracje systemowe,
- testy i CI,
- uzasadnienia kluczowych decyzji technicznych (na podstawie kodu i istniejacych checklist).

---

# 2. Produkt i funkcje

## 2.1 Funkcje podstawowe (free)

- Pomiary metryk (wiele rodzajow, w tym obwody, waga, sklad ciala).
- Szybkie dodawanie (Quick Add) z formularzem i suwakiem "ruler".
- Cele per metryka (trend pozytywny/negatywny zalezy od celu lub domyslnej preferencji).
- Zdjecia progresu z tagami (np. waist, wholeBody) i przypisanymi snapshotami metryk.
- Widoki:
  - Home (podsumowanie, kluczowe metryki, ostatnie zdjecia, checklista onboardingu),
  - Measurements (wykresy, trendy),
  - Photos (siatka, selekcja, porownanie 2 zdjec),
  - Settings (ustawienia, diagnostyka, dane).
- Lokalizacja: EN + PL (`MeasureMe/en.lproj`, `MeasureMe/pl.lproj`).

## 2.2 Funkcje premium

Premium odblokowuje (wg UI i README):
- AI Insights (wymaga premium + Apple Intelligence),
- Health indicators (czesc widoku Measurements),
- Data export (CSV),
- Photo comparison tools.

StoreKit product IDs:
- `com.measureme.premium.monthly`
- `com.measureme.premium.yearly`

Konfiguracja StoreKit do testow lokalnych:
- `Premium.storekit` (w repo jest tez `MeasureMe/Premium.storekit` wspomniane w README)

---

# 3. Wymagania platformowe

- iOS deployment target: **17.2** (ustawienia projektu).
- Xcode: w praktyce **26.2+** (README + CI wybiera Xcode 26.2).
- Urzadzenia: iPhone only (`TARGETED_DEVICE_FAMILY = 1` w projekcie).
- Orientacja: portrait only na iPhone (build setting `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait`).
- Apple Intelligence / AI Insights:
  - tylko na fizycznym urzadzeniu (na symulatorze jest wylaczone),
  - wymaga iOS **26+**,
  - wymaga dostepnosci modelu (`FoundationModels` / `SystemLanguageModel`).

---

# 4. Architektura (high-level)

## 4.1 Glowne filary

- **SwiftUI** jako warstwa UI.
- **SwiftData** jako persystencja (modele oznaczone `@Model`).
- **UserDefaults/AppStorage** jako persystencja preferencji, flag i lekkiego stanu UI.
- **Serwisy/Manager-y** dla integracji:
  - HealthKit (sync, import, background delivery),
  - powiadomienia,
  - premium/StoreKit,
  - crash reporting,
  - pipeline obrazow.

## 4.2 Wejscie aplikacji i bootstrap

Plik startowy:
- `MeasureMe/MeasureMeApp.swift`

Bootstrap (w skrocie):
1. Instalacja crash reporting (`CrashReporter.shared.install()`).
2. Rejestracja domyslnych wartosci UserDefaults (`register(defaults:)`) dla kluczy aplikacji.
3. Inicjalizacja `ModelContainer` dla SwiftData (schema: `MetricSample`, `MetricGoal`, `PhotoEntry`).
4. Tryby testowe (UI tests) moga:
   - czyscic dane,
   - seedowac dane pomiarow,
   - wymuszac preferencje (np. premium, jezyk).
5. Ustawienie Data Protection na katalogi i potencjalne pliki store (`DatabaseEncryption.applyRecommendedProtection()`).
6. Harmonogram "smart reminders" (`NotificationManager.shared.scheduleSmartIfNeeded()`).
7. Konfiguracja HealthKit (`HealthKitManager.shared.configure(...)`, reconcile i start obserwacji).

## 4.3 Kompozycja UI i nawigacja

- Root warstwa:
  - `MeasureMe/RootView.swift`
  - Wstrzykuje `PremiumStore` i `ActiveMetricsStore` przez `environmentObject`.
  - Pokazuje onboarding overlay, jesli `hasCompletedOnboarding == false`.
  - Obsluguje dialog po zakupie trial dot. wlaczenia przypomnien.

- Nawigacja/taby:
  - `MeasureMe/TabBarContainer.swift`
  - `AppRouter` jako `ObservableObject` z:
    - `selectedTab: AppTab`
    - `presentedSheet: PresentedSheet?`
  - Compose tab w praktyce otwiera sheet QuickAdd (nie przechodzi na osobny ekran).

## 4.4 Watek glowny i wspolbieznosc

Wzorce:
- UI i wiekszosc store-ow jest `@MainActor` (bezpieczne dla SwiftUI).
- Cache dyskowy obrazow jest `actor` (`DiskImageCache`) dla bezpiecznej wspolbieznosci.
- AI Insights generowane w `actor MetricInsightService` z cache i kontrola `inFlight`.
- Image downsampling w `Task.detached` (pipeline), a zapis do cache wroc na MainActor dla `ImageCache`.

---

# 5. Dane i persystencja (SwiftData)

## 5.1 Modele danych

SwiftData `@Model`:
- `MeasureMe/MetricSample.swift`
  - `kindRaw: String` (rawValue z `MetricKind`)
  - `value: Double` (zawsze w jednostkach bazowych metrycznych)
  - `date: Date`
  - computed `kind: MetricKind?` (bez fallbacku dla zlego `kindRaw`)

- `MeasureMe/MetricGoal.swift`
  - `kindRaw: String`
  - `targetValue: Double` (w jednostkach bazowych)
  - `createdDate: Date`
  - `directionRaw: String` (increase/decrease)

- `MeasureMe/PhotoEntry.swift`
  - `@Attribute(.externalStorage) imageData: Data`
  - `date: Date`
  - `tags: [PhotoTag]`
  - `linkedMetrics: [MetricValueSnapshot]`

Wazne typy pomocnicze:
- `MeasureMe/MetricKind.swift` – enum wszystkich metryk + konwersja jednostek + metadata (title, ikonka).
- `MeasureMe/PhotoTag.swift` – enum tagow zdjec + mapowanie z `MetricKind` (bez weight/bodyFat/leanBodyMass jako tagow).
- `MeasureMe/MetricValueSnapshot.swift` – snapshot metryki przypisany do zdjecia (uzywany w Photos).

## 5.2 Jednostki i konwersja

Kontrakt:
- baza zapisu: **metryczne** (kg, cm, % w skali 0–100),
- UI moze pracowac w metric/imperial (`unitsSystem`),
- konwersja tylko na granicy UI/serializacji:
  - `MetricKind.valueForDisplay(fromMetric:unitsSystem:)`
  - `MetricKind.valueToMetric(fromDisplay:unitsSystem:)`

## 5.3 Lokalizacja bazy danych

`ModelContainer` jest tworzony z konfiguracja nie-in-memory (produkcyjnie).
SwiftData store fizycznie laduje w katalogach aplikacji (np. Application Support).

## 5.4 "Encryption at rest" (Data Protection)

- `MeasureMe/DatabaseEncryption.swift`
- Mechanizm: ustawianie `FileProtectionType.completeUntilFirstUserAuthentication` na katalogi oraz podejrzane pliki `.store`/SQLite/WAL/SHM.
- Intencja: dane zaszyfrowane "w spoczynku", ale dostepne po pierwszym odblokowaniu (kompatybilne z background delivery HealthKit).

---

# 6. Kluczowe moduly i przeplywy

## 6.1 Home

Glowny ekran:
- `MeasureMe/HomeView.swift`

Odpowiedzialnosci:
- wyswietlenie kluczowych metryk (max 3) z `ActiveMetricsStore.keyMetrics`,
- ostatnie zdjecia (max 6),
- checklista onboardingowa (sterowana AppStorage),
- wejscie do QuickAdd (`home.quickadd.button` w UI tests),
- opcjonalne sekcje (toggle w Settings: measurements/photos/health metrics on home),
- cache danych pochodnych (samplesByKind, latestByKind, goalsByKind) z ograniczaniem pracy w `body`.

## 6.2 Measurements

Zakladka:
- `MeasureMe/MeasurementsTabView.swift`

Funkcje:
- lista kafelkow wykresow dla aktywnych metryk,
- segment "Metrics" vs "Health indicators":
  - wejscie w "Health indicators" jest blokowane paywallem, gdy brak premium,
  - przy premium pokazuje `HealthMetricsSection`.

## 6.3 Quick Add

Sheet:
- `MeasureMe/QuickAddSheetView.swift`

Zapis i sync:
- `MeasureMe/QuickAddSaveService.swift`
  - zapisuje `MetricSample` do SwiftData,
  - opcjonalnie robi best-effort sync do HealthKit (bledy polykane, logowane).

Walidacja i UX:
- `MeasureMe/MetricInputValidator.swift`
- `MeasureMe/QuickAddMath.swift` (pomocnicza matematyka dla suwaka/range/tickow).

## 6.4 Photos

Zakladka:
- `MeasureMe/PhotoView.swift`
  - grid, selekcja, porownanie 2 zdjec, filtry.

Dodawanie zdjec:
- `MeasureMe/Photos/AddPhotoView.swift`
  - optymalizuje obraz (resize/kompresja),
  - zapisuje `PhotoEntry` (external storage),
  - tworzy snapshoty metryk na zdjeciu,
  - dodatkowo wstawia `MetricSample` dla wpisanych metryk z ta sama data.

Szczegoly zdjecia:
- `MeasureMe/Photos/PhotoDetailView.swift`
  - zapis do galerii (Photos),
  - obsluga bledow permission/performChanges.

## 6.5 Settings

Glowny widok:
- `MeasureMe/SettingsView.swift`

Moduly:
- premium: prezentacja paywalla z powodami (AI insights, export, health indicators),
- zdrowie: wlaczenie sync (HealthKit), statusy i ostatni import,
- notyfikacje: zarzadzanie przypomnieniami,
- dane:
  - export metrics CSV (premium),
  - export diagnostics JSON (share sheet),
  - crash reports,
  - delete all data (lokalnie).

Delete all data:
- kasuje SwiftData encje (MetricSample, MetricGoal, PhotoEntry),
- resetuje NotificationManager (`resetAllData()`),
- czyści metadane sync HealthKit (anchory, last processed),
- czyści czesc kluczy UserDefaults,
- czyści cache obrazow (memory + disk),
- **nie usuwa danych z Apple Health** (komunikat w UI).

---

# 7. Integracje systemowe

## 7.1 HealthKit

Plik:
- `MeasureMe/HealthKitManager.swift`

Strategia:
- Abstrakcja `HealthStore` (protocol) + `RealHealthStore` (HKHealthStore) dla testow jednostkowych bez prawdziwego HealthKit.
- Sync wspieranych typow (w kodzie m.in.):
  - weight (bodyMass),
  - bodyFatPercentage,
  - height,
  - leanBodyMass,
  - waistCircumference,
  - dodatkowo BMI (bodyMassIndex) dla odczytu/zapisu.

Import:
- "initial historical import" dla subsetu metryk (waga, bodyFat, leanBodyMass, waist) z flaga `healthkit_initial_historical_import_v1`.
- Dalszy import oparty o `HKAnchoredObjectQuery` + anchory zapisywane w UserDefaults (`healthkit_anchor_<kind>`).
- Ochrona przed duplikatami: okno tolerancji czasu + tolerancja wartosci (deduplikacja).

Background delivery:
- observer query + `enableBackgroundDelivery(..., frequency: .immediate)`.

Uprawnienia:
- entitlements: `MeasureMe/MeasureMe.entitlements` (HealthKit + background delivery).
- manager zwraca user-facing komunikaty bledow dla stanów denied/not available.

## 7.2 Powiadomienia (UserNotifications)

Plik:
- `MeasureMe/NotificationManager.swift`

Wzorce:
- `NotificationCenterClient` (protocol) + `RealNotificationCenterClient` dla testow.
- Przypomnienia:
  - manualne (once/daily/weekly),
  - smart reminder (gdy nie logowano od X dni),
  - photo reminder (gdy brak zdjec od X dni),
  - trial ending reminder (po zakupie trial, 12 dni),
  - import summary (z buforem 15s, agreguje rodzaje metryk).
- Reset danych usuwa tylko requesty "owned" przez aplikacje (po identifier/prefix).

## 7.3 StoreKit 2 (Premium)

Plik:
- `MeasureMe/PremiumStore.swift`

Wzorce:
- `PremiumBillingClient` dla izolacji StoreKit i testowania.
- `PremiumNotificationManaging` (adapter na `NotificationManager`) dla flow po trial.
- Flow:
  - ladowanie produktow,
  - purchase/restore,
  - entitlements z `Transaction.currentEntitlements` i `Transaction.updates`,
  - "seven day prompt" paywalla po 7 dniach od pierwszego uruchomienia.

## 7.4 Photos / Camera

- UI: `MeasureMe/CameraPickerView.swift`, `MeasureMe/Photos/*`.
- Zapis do Photos (galerii) przez `PHPhotoLibrary.performChanges`.
- Wymaga odpowiednich opisow uprawnien (w praktyce utrzymywanych w Build Settings).

---

# 8. Obrazy i cache (pipeline)

Komponenty:
- `MeasureMe/ImageCache.swift`
  - memory cache (NSCache) + LRU lista dostepu,
  - reaguje na memory warning (`UIApplication.didReceiveMemoryWarningNotification`) i czyści cache.

- `MeasureMe/DiskImageCache.swift`
  - `actor`, zapis w `Caches/MeasureMeImageCache`,
  - nazwy plikow hashowane (SHA-256) gdy `CryptoKit` dostepne,
  - ustawione Data Protection na katalog cache (best-effort).

- `MeasureMe/ImageDownsampler.swift`
  - downsample przez ImageIO (`CGImageSourceCreateThumbnailAtIndex`) z transform.

- `MeasureMe/ImagePipeline.swift`
  - kolejnosc: memory -> disk -> downsample -> zapis do cache.

Cel architektury pipeline:
- minimalizowac dekodowanie i przetwarzanie obrazow,
- utrzymac spojnosc w wielu ekranach,
- uniknac blokowania UI (detached task dla downsamplingu).

---

# 9. Diagnostyka i crash reporting

## 9.1 CrashReporter

Plik:
- `MeasureMe/CrashReporter.swift`

Funkcje:
- circular buffer ostatnich logow (200 wpisow),
- przechwytywanie `NSException` przez `NSSetUncaughtExceptionHandler`,
- zapisywanie raportow `.crash` do `Application Support/CrashReports/`,
- flaga "unreported crash" w UserDefaults,
- generowanie "diagnostic report" (bez crash) do wysylki.

Logowanie aplikacji:
- `MeasureMe/AppLog.swift`
  - w DEBUG drukuje do konsoli,
  - w release zalezy od `diagnostics_logging_enabled` (domyslnie true, jesli brak ustawienia),
  - logi trafiaja do CrashReporter (appendLog).

## 9.2 UI do crash reports

Plik:
- `MeasureMe/CrashReportView.swift`

Sciezka:
- Settings → Data → Crash Reports

Mozliwosci:
- lista raportow,
- podglad (monospace, selectable),
- udostepnianie (share sheet),
- kasowanie raportu,
- wyslanie diagnostic report (logi) bez crasha.

---

# 10. Prywatnosc i bezpieczenstwo

## 10.1 Zasady prywatnosci (z kodu i README)

- Dane sa przechowywane lokalnie (offline-first).
- Integracje (HealthKit, notyfikacje, Photos/Camera) sa opt-in lub user-driven.
- Export/sharing jest inicjowany przez uzytkownika.
- Brak tracking (privacy manifest).

## 10.2 Privacy manifest

Plik:
- `MeasureMe/PrivacyInfo.xcprivacy`

Deklaruje m.in.:
- accessed API: UserDefaults (reason `CA92.1`),
- accessed API: FileTimestamp (reason `C617.1`),
- collected data: none,
- tracking: false.

## 10.3 Data Protection

Patrz:
- `MeasureMe/DatabaseEncryption.swift` (ochrona store i katalogow),
- `MeasureMe/DiskImageCache.swift` (ochrona cache na dysku).

---

# 11. Testy (unit, snapshot, UI)

## 11.1 Struktura targetow testowych

- `MeasureMeTests` – unit + snapshot tests.
- `MeasureMeUITests` – UI tests (XCUITest).

## 11.2 Unit tests – przyklady i podejscie

Testy pokrywaja m.in.:
- HealthKit authorization i reconcile (mock `HealthStore`): `MeasureMeTests/HealthKitManagerAuthorizationTests.swift`
- logika premium i trial reminders: `MeasureMeTests/PremiumStoreTests.swift`
- notyfikacje (mock `NotificationCenterClient`): `MeasureMeTests/NotificationManagerTests.swift`
- domena/metyka:
  - kalkulator wskaznikow zdrowotnych: `MeasureMeTests/HealthMetricsCalculatorTests.swift`
  - konwersje i trend logic: `MeasureMeTests/MetricKindTests.swift`
  - walidacja: `MeasureMeTests/MetricInputValidatorTests.swift`
- cache/pipeline obrazow: `MeasureMeTests/ImageCachePipelineTests.swift`
- integracja persystencji SwiftData (in-memory): `MeasureMeTests/PersistenceAndModelIntegrityTests.swift`
- QuickAddSaveService (kontrakt sync i odporność na bledy): `MeasureMeTests/QuickAddSaveServiceTests.swift`

## 11.3 Snapshot tests

- Uzywany framework: `SnapshotTesting` (SPM).
- Przyklad: `MeasureMeTests/RootViewSnapshotTests.swift`
- Snapshoty trzymane w `MeasureMeTests/__Snapshots__/`.

## 11.4 UI tests

Pliki m.in.:
- `MeasureMeUITests/MeasureMeUITests.swift` (smoke + wybrane scenariusze)
- `MeasureMeUITests/OnboardingUITests.swift`
- `MeasureMeUITests/QuickAddUITests.swift`
- `MeasureMeUITests/HomeViewUITests.swift`

### Launch arguments (wspierane w kodzie)

Wykorzystane do deterministycznych testow i mockowania stanow:
- `-uiTestMode` (ustawia hasCompletedOnboarding, premium, jezyk, metryki domyslne, itp.)
- `-uiTestOnboardingMode` (wymusza onboarding flow)
- `-uiTestNoActiveMetrics` (wyłącza metryki)
- `-uiTestSeedMeasurements` (seed danych pomiarow)
- `-uiTestHealthAuthDenied` (symuluje odmowe HealthKit)
- `-uiTestHealthAuthUnavailable` (symuluje brak HealthKit)
- `-uiTestForcePremium` (wymusza entitlement premium w UI)
- `-uiTestForceAIAvailable` (wymusza dostępność AI insights)
- `-uiTestLongInsight` / `-uiTestLongHealthInsight` (wymusza długi tekst w UI)
- `-uiTestBypassHealthSummaryGuards` (bypass guardow w sekcji health summary na Home)

---

# 12. CI (GitHub Actions)

Workflow:
- `.github/workflows/ios-ci.yml`

Co robi:
- instaluje SwiftLint (`brew install swiftlint`),
- lintuje zmienione pliki Swift w trybie strict (blokujace),
- generuje pelny raport lint (non-blocking),
- wybiera Xcode 26.2,
- buduje, (opcjonalnie) uruchamia analyze (non-blocking), uruchamia testy,
- matrix na iOS runtimes: `18.0` i `26.1` (z fallbackiem, gdy konkretna wersja symulatora nie istnieje na runnerze).

---

# 13. Developer workflow (build/run/lint)

## 13.1 Uruchomienie w Xcode

1. Otworz `MeasureMe.xcodeproj`.
2. Scheme: `MeasureMe`.
3. Simulator lub device.
4. Run: `Cmd+R`.

## 13.2 xcodebuild (CLI)

Build (symulator):
```
xcodebuild \
  -project MeasureMe.xcodeproj \
  -scheme MeasureMe \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.1' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Test:
```
xcodebuild \
  -project MeasureMe.xcodeproj \
  -scheme MeasureMe \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.1' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Analyze (opcjonalnie):
```
xcodebuild \
  -project MeasureMe.xcodeproj \
  -scheme MeasureMe \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.1' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  analyze
```

## 13.3 SwiftLint

Konfiguracja:
- `.swiftlint.yml` (minimalny zestaw `only_rules` + excluded derived data)

Lint:
```
swiftlint lint --config .swiftlint.yml
```

---

# 14. Zaleznosci

## 14.1 Apple frameworks (wykorzystywane w kodzie)

- SwiftUI
- SwiftData
- HealthKit
- StoreKit (StoreKit 2)
- UserNotifications
- Charts
- Photos / PhotoKit
- UIKit (np. share sheet, UIAppearance, textfield selectAll)
- CryptoKit (hashing cache)
- ImageIO (downsampling)
- FoundationModels (warunkowo, dla Apple Intelligence)

## 14.2 Swift Package Manager (SPM)

Z `Package.resolved` (workspace SwiftPM):
- `pointfreeco/swift-snapshot-testing` (snapshot tests)
- `pointfreeco/swift-custom-dump` (pomoc testowa)
- `pointfreeco/xctest-dynamic-overlay`
- `swiftlang/swift-syntax` (transitive / tooling)

---

# 15. Konfiguracja (UserDefaults/AppStorage)

W aplikacji jest duzo kluczy. Najwazniejsze grupy:

## 15.1 Stan aplikacji i onboarding

- `hasCompletedOnboarding`
- `onboarding_*` (checklista, pominiete kroki, stan UI)
- `appLanguage` (`system` / `en` / `pl`)

## 15.2 Metryki i jednostki

- `unitsSystem` (`metric` / `imperial`)
- `metric_<kind>_enabled` (wlaczenie metryki)
- `metrics_active_order` (kolejnosc)
- `home_key_metrics` (max 3)

## 15.3 Premium i AI

- `premium_entitlement`
- `premium_first_launch_date`
- `premium_last_nag_date`
- `apple_intelligence_enabled`

## 15.4 HealthKit

- `isSyncEnabled`
- `healthkit_sync_<kind>`
- `healthkit_last_import`
- `healthkit_anchor_<kind>` i `healthkit_last_processed_<kind>`
- `healthkit_initial_historical_import_v1`

## 15.5 Notyfikacje

- `measurement_notifications_enabled`
- `measurement_reminders`
- `measurement_smart_enabled`, `measurement_smart_days`, `measurement_smart_time`
- `measurement_last_log_date`
- `photo_last_log_date`
- `measurement_photo_reminders_enabled`
- `measurement_goal_achieved_enabled`
- `measurement_import_notifications_enabled`

## 15.6 Diagnostyka

- `diagnostics_logging_enabled`

---

# 16. Ograniczenia i znane ryzyka

- AI Insights:
  - nie dziala w symulatorze,
  - wymaga iOS 26+ i urzadzenia wspieranego przez Apple Intelligence.
- Distribution signing / App Store:
  - w checklistach release sa odnotowane problemy z exportem archiwum bez poprawnych profili dystrybucyjnych.
- HealthKit:
  - integracja jest wrazliwa na uprawnienia i stan systemu; aplikacja ma mechanizmy rollbacku toggla i user-facing error message.
- Dane:
  - `Delete all data` nie usuwa danych z Apple Health (celowo).
- Projekt jest iPhone-only i portrait-only (celowo, ale ogranicza UX na iPadzie).

---

# 17. Zalaczniki

## 17.1 Mapa repo

- `MeasureMe/` – kod aplikacji
- `MeasureMe/Photos/` – ekrany i utility zwiazane ze zdjeciami
- `MeasureMeTests/` – unit + snapshot
- `MeasureMeUITests/` – UI tests
- `.github/workflows/ios-ci.yml` – CI
- `README.md` – szybki opis, komendy, CI
- `APP_STORE_PREFLIGHT_2026-02-12.md` – checklista preflight
- `RELEASE_SUBMISSION_CHECKLIST_2026-02-12.md` – checklista publikacji
- `DEVICE_TEST_CHECKLIST_IOS18_IOS26_IPHONE_PORTRAIT.md` – manualne testy na fizycznych urzadzeniach

## 17.2 Szybkie komendy

```
swiftlint lint --config .swiftlint.yml
```

```
xcodebuild -project MeasureMe.xcodeproj -scheme MeasureMe -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.1' -configuration Debug CODE_SIGNING_ALLOWED=NO test
```

