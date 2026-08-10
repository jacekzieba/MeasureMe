# Model 3D sylwetki — design

Data: 2026-08-10
Status: zatwierdzony do planowania

## 1. Cel

Zamienić wprowadzone przez użytkownika obwody ciała w uproszczoną, trójwymiarową
sylwetkę i pokazać jej zmianę w czasie jako płynny morf między dwoma pomiarami.

Feature **nie** jest skanem ciała ani awatarem. To manekin krawiecki: forma bez
twarzy, dłoni i stóp, bez cech osobowych. Wierność dotyczy proporcji i objętości,
nie wyglądu.

## 2. Decyzje produktowe

| Decyzja | Wybór |
|---|---|
| Umiejscowienie | Osobny ekran w zakładce Photos, obok Compare |
| Morf | Dwie wybrane daty, A→B (wzorzec z Compare Photos) |
| Kompletność danych | Wymagane wszystkie metryki, okno ±14 dni |
| Lewa/prawa strona | Uśredniane |
| Płeć | Dwie bazowe siatki, płeć wymagana |
| Realizm | Uproszczony manekin, bez cech osobowych |
| Walidacja objętości | Wymagana |
| Dostępność | Premium |

## 3. Wymagane dane

Po uśrednieniu lewej i prawej strony — trzynaście wartości dla kobiet,
dwanaście dla mężczyzn:

`height`, `weight`, `bodyFat`, `neck`, `shoulders`, `chest`, `bust` (tylko K),
`waist`, `hips`, `bicep`, `forearm`, `thigh`, `calf`

Plus z profilu: `userGender` (male/female), `userAge`.

`leanBodyMass` jest **świadomie wykluczona** z zestawu wymaganego — to
`weight × (1 − bodyFat)`, czyli zero niezależnej informacji przy niezerowym
koszcie wejścia dla użytkownika.

`bust` jest wymagana wyłącznie dla `gender == .female`. Dla mężczyzn obwód
klatki niesie tę samą informację.

### Definicja `shoulders`

`MetricKind.insightMeasurementContext` klasyfikuje `shoulders` jako
*body circumference*. Solver przyjmuje tę interpretację. Przed implementacją
należy potwierdzić, że instrukcja pomiaru w onboardingu również mówi o obwodzie,
a nie o szerokości barków — rozbieżność systematycznie zniekształci górną partię
sylwetki.

## 4. Architektura

Pierwsze sześć jednostek to czysty Swift bez importu SceneKit — cała matematyka
jest testowalna bez renderowania.

| Jednostka | Wejście → wyjście | Odpowiedzialność |
|---|---|---|
| `BodySnapshot` | — | Wartość: 13 metryk (jednostki metryczne), gender, age, zakres dat. `Sendable` |
| `BodySnapshotBuilder` | `[MetricSample]` + data kotwicząca → `BodySnapshot` \| lista braków | Okno ±14 dni, uśrednianie L/P, kontrola kompletności |
| `BodyProportions` | — | Tablice antropometryczne: pozycje landmarków jako ułamki wzrostu, aspect ratio i wykładniki superelipsy per site, per gender. Stała, zero logiki |
| `BodyMeshParameters` | — | ~20 poziomów: `y`, obwód, aspect, wykładnik. Jednostka interpolowana przy morfie |
| `BodyMeshSolver` | snapshot + proporcje → parametry | Mapowanie pomiarów na kotwice, interpolacja między nimi, dopasowanie do masy |
| `BodyVolumeValidator` | parametry + snapshot → `ValidationResult` | Objętość analityczna, gęstość z `bodyFat`, odchyłka od `weight` |
| `BodyGeometryBuilder` | parametry → `SCNGeometry` | Wierzchołki, triangulacja, normalne. Stała topologia |
| `BodyMorphViewModel` | snapshot A, B, `t` | Interpolacja parametrów, stan ekranu |
| `MannequinView` / `BodyModelScreen` | — | `SCNView` w `UIViewRepresentable`; ekran w Photos |

Granica: wszystko powyżej `BodyGeometryBuilder` nie wie o istnieniu SceneKit.
`MannequinView` jest jedynym miejscem w kodzie, które importuje SceneKit.

## 5. Model geometryczny

Ciało to ~20 poziomych przekrojów wzdłuż osi Y. Przekrój to superelipsa:

```
|x/a|ⁿ + |z/b|ⁿ = 1
```

- obwód pochodzi z pomiaru użytkownika
- stosunek `b/a` i wykładnik `n` z `BodyProportions`, per site i per gender
  (talia `n ≈ 2,3`; klatka `n ≈ 2,6`; kończyny `n = 2`, czyli elipsa)
- z obwodu, aspect ratio i `n` wyznaczamy `a` i `b` numerycznie — obwód
  superelipsy nie ma postaci zamkniętej

Pole przekroju **ma** postać zamkniętą:

```
A = 4ab · Γ(1 + 1/n)² / Γ(1 + 2/n)
```

Dzięki temu objętość liczymy trapezami po poziomach, bez całkowania po siatce.

Kończyny są loftowanymi rurami o przekroju eliptycznym, budowanymi z tych samych
parametrów. Ponieważ uśredniamy L/P, budujemy jedną kończynę i odbijamy ją
lustrzanie; objętość liczymy podwójnie.

### Pozycje pionowe

Pomiary nie zawierają żadnej długości segmentu — znamy tylko `height`. Pozycje
landmarków (szyja, barki, klatka, talia, biodra, krocze, kolano, kostka) pochodzą
z `BodyProportions` jako ułamki wzrostu, per gender, oparte na percentylach
ANSUR II i współczynnikach Drillis–Contini. Wartości są zaszyte na stałe i
kalibrowane testem walidatora (sekcja 12, punkt 3).

Obwody między poziomami kotwiczącymi wyznacza monotoniczna interpolacja
(Fritsch–Carlson), żeby uniknąć oscylacji charakterystycznych dla splajnów
kubicznych — sylwetka nie może falować między talią a biodrami.

## 6. Walidacja objętości

Gęstość z dwuskładnikowego modelu Siriego:

```
ρ = 1 / (bf/0,9 + (1 − bf)/1,1)      [g/cm³]
```

Masa przewidziana = `ρ × V`, porównywana z `weight`.

### Korekta

Przy rozbieżności **nie skalujemy przekrojów** — zmieniłoby to obwody, czyli
skłamało o danych użytkownika. Zmienną korygowaną jest **podział wzrostu między
tors a nogi**, czyli jedyna wielkość, której realnie nie znamy. Wzrost jest
zmierzony i pozostaje stały, ale tors ma znacznie większy przekrój niż nogi, więc
przesunięcie tego podziału silnie zmienia objętość przy zachowanym wzroście.

Zakres korekty: **±6%** od normy populacyjnej. Poza tym zakresem nie dopasowujemy
na siłę — raportujemy rozjazd.

### Progi

| Odchyłka masy | Zachowanie |
|---|---|
| ≤ 5% | Sylwetka, bez komunikatu |
| 5–12% | Sylwetka + notka o przybliżeniu |
| > 12% | Sylwetka + wskazanie metryki o największym wkładzie do rozbieżności, sugestia ponownego pomiaru |

Trzeci próg zamienia walidację w funkcję produktową: aplikacja wyłapuje błędny
pomiar. Wkład metryki liczymy jako pochodną objętości po tej metryce, przemnożoną
przez jej odchylenie od normy populacyjnej dla danego wzrostu i płci.

## 7. Morf

Interpolujemy `BodyMeshParameters` — obwody, aspect ratio, pozycje `y` — liniowo
po `t ∈ [0,1]`. **Nie interpolujemy wierzchołków.** Topologia jest stała, więc
podmieniamy wyłącznie bufor pozycji: zero artefaktów, zero alokacji per klatka.

Niezmiennik: dla każdego poziomu i każdego `t` obwód leży między wartością A i B.

Skala: ~20 przekrojów × 32 segmenty + kończyny ≈ 1500 wierzchołków. Bez znaczenia
wydajnościowego.

## 8. UI i spójność wizualna

Ekran żyje w Photos, więc akcent to `FeatureTheme.photos` (→
`AppColorRoles.accentPhoto`), **nie** bursztynowy `.appAccent`. Wszystkie tinty
kart i kontrolek pochodzą z tego jednego źródła.

| Element | Komponent | Źródło |
|---|---|---|
| Panel wyboru dat, panel jakości | `AppGlassCard(tint:)` | `AppGlass.swift` |
| Suwak morfu | `Slider` w `AppGlassCard` | wzorzec `ghostOpacity`, `ComparePhotosView.swift:486` |
| Przycisk odtwarzania | `LiquidCapsuleButtonStyle(tint:)` | `AppGlass.swift` |
| Lista zmian pod manekinem | `MetricChange` + `MetricChangeRow` | `ComparePhotosView.swift:941` — reużywamy |
| Stany puste | `EmptyStateCard` | `DesignSystem/AppStateComponents.swift:3` |
| Odstępy, promienie, typografia | `AppSpacing`, `AppRadius`, `AppTypography` | DesignSystem |
| Teksty | `AppLocalization.string(...)` | konwencja apki |
| Haptyka przy zmianie daty | `Haptics.selection()` | konwencja |

Manekin: matowy materiał w `FeatureTheme.photos.accent` z delikatnym rimlightem.
Czytelny na obu tłach i podkreślający formę krawiecką zamiast człowieka.

### Pułapka: SCNView a dark mode

`SCNView` nie reaguje samodzielnie na zmianę `colorScheme`. Materiał manekina,
kolor tła sceny i oświetlenie muszą być przeliczane z `AppColorRoles` w
`updateUIView` przy każdej zmianie schematu. Bez tego light mode pokaże ciemną
plamę. To jedyne miejsce, gdzie 3D wychodzi poza system designu, i jest zamknięte
w `MannequinView`.

### Interakcja

- Obrót manekina gestem poziomym (pełne 360°)
- Bez zoomu i bez obrotu w pionie w MVP
- Suwak morfu `t` od A do B
- Przycisk odtwarzania: animacja 1,5 s tam i z powrotem

## 9. Premium

Manekin jest funkcją premium. Bramkowanie zgodne z istniejącym wzorcem:
`@EnvironmentObject private var premiumStore: PremiumStore` i `premiumStore.isPremium`
(jak `MeasurementsTabView.swift:477`).

Ekran jest osiągalny dla wszystkich i pokazuje zablokowany stan zachęcający;
akcja otwiera paywall. Nie stosujemy twardej blokady wejścia — podgląd tego, co
się dostaje, konwertuje lepiej niż zamknięte drzwi.

Telemetria używa istniejącego `PaywallTelemetrySource.feature` z
`reason: "body_model"`. Nowy case enuma nie jest potrzebny.

Tryb testów UI honoruje istniejący wzorzec `premiumStore.isPremium || uiTestModeEnabled`
(`PhotoView.swift:129`).

## 10. Stany brzegowe

| Stan | Zachowanie |
|---|---|
| Brak premium | Zablokowany stan zachęcający, akcja → paywall |
| `userGender` = notSpecified lub `manualHeight` = 0 | `EmptyStateCard`, akcja → profil w Settings |
| 0 kompletnych snapshotów | `EmptyStateCard` z listą brakujących metryk, akcja → QuickAdd |
| Dokładnie 1 snapshot | Statyczna sylwetka; suwak i drugi picker ukryte |
| ≥ 2 snapshoty | Pełny morf A→B |
| Odchyłka masy > 12% | Karta ostrzegawcza ze wskazaną metryką — nie `InlineErrorBanner`, bo to nie jest błąd aplikacji |

Wybór dat ograniczony wyłącznie do dat, dla których istnieje kompletny snapshot.

## 11. Dostępność

Morf przechodzi przez `AppMotion.shouldAnimate(animationsEnabled:reduceMotion:)`,
tak jak reszta aplikacji. Przy zredukowanym ruchu suwak pozostaje (to gest
użytkownika), znika automatyczne odtwarzanie.

Geometria 3D jest dla VoiceOver niewidzialna. Dlatego:

- manekin dostaje `accessibilityLabel` opisujący sylwetkę słownie
- **realną treścią dostępną jest lista `MetricChangeRow` pod manekinem** — osoba
  niewidoma otrzymuje pełną informację o zmianie, bez utraty treści

Identyfikatory w konwencji `photos.bodyModel.*`, zgodnie z istniejącym
`photos.compare.modePicker`.

## 12. Testy

1. `BodySnapshotBuilder` — okno ±14 dni na granicach (13/14/15 dni), uśrednianie
   L/P, wykrywanie braków, `bust` wymagana tylko dla kobiet
2. **`BodyMeshSolver` — niezmiennik odtworzenia obwodów.** Obwód wyliczony na
   każdym poziomie kotwiczącym musi równać się zmierzonemu z dokładnością
   < 0,5 mm. Pierwszy test do napisania; na nim stoi wiarygodność feature'u
3. `BodyVolumeValidator` — dla percentyli ANSUR II 5/50/95 obu płci odchyłka
   masy < 5%. To test poprawności modelu, nie kodu; służy też do kalibracji
   `BodyProportions`
4. Morf — monotoniczność: obwód na każdym poziomie dla `t ∈ [0,1]` leży między
   wartością A i B
5. Snapshot testy ekranu z **jawnym** ustawieniem wszystkich odpowiednich kluczy
   UserDefaults w `configureDefaults` — inaczej stan wycieka między biegami
6. UITest bramkowania premium przez `uiTestModeEnabled`

## 13. Poza zakresem MVP

Świadomie pominięte: zoom i obrót w pionie, tryb „teraz vs cel", suwak po pełnej
osi czasu, asymetria lewej i prawej strony, eksport sylwetki do obrazu,
udostępnianie, dopasowanie na podstawie zdjęć z `PhotoEntry`.

## 14. Ryzyka

| Ryzyko | Ograniczenie |
|---|---|
| Manekin wygląda jak figura z tokarki | Świadoma decyzja produktowa; przejście szyja–barki–tors wymaga ręcznego strojenia `BodyProportions` |
| Bardzo niewielu użytkowników skompletuje 13 metryk | Okno ±14 dni; stan pusty jawnie wymienia braki i prowadzi do QuickAdd; przy 1 snapshocie feature już działa |
| Wrażliwość na obraz własnego ciała | Forma bez cech osobowych, brak ocen i porównań do norm w UI |
| Rozbieżność definicji `shoulders` | Do potwierdzenia przed implementacją (sekcja 3) |
| Percepcja dokładności | Panel jakości komunikuje przybliżenie wprost, zamiast sugerować precyzję skanu |
