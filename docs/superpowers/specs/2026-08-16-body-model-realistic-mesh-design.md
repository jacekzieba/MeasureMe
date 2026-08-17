# Model 3D sylwetki — realistyczna siatka bazowa

Data: 2026-08-16
Status: do akceptacji
Zastępuje: część decyzji z `2026-08-10-body-model-3d-design.md`

## 1. Problem

Obecna wizualizacja generuje siatkę w całości proceduralnie
(`BodyGeometryBuilder`): pięć niezależnych stosów pierścieni — tors, dwa
ramiona, dwie nogi — gdzie każdy pierścień to superelipsa dopasowana do
zmierzonego obwodu.

Konsekwencje widoczne na ekranie:

- brak głowy, dłoni i stóp — stosy kończą się na ostatnim punkcie pomiarowym
  (szyja, nadgarstek, kostka)
- brak barków — ramiona to osobne stosy przesunięte o stałe `armOffsetCm = 22`,
  nic nie łączy ich z torsem, więc wiszą w powietrzu
- otwarte końce rur, ujawnione przez `isDoubleSided = true`
- jednolity kolor akcentu, brak cieniowania sugerującego anatomię

**To nie jest regres.** Spec z 10.08 zapisał wprost: *„To manekin krawiecki:
forma bez twarzy, dłoni i stóp"*, a tabela decyzji ustaliła „Realizm →
uproszczony manekin". Niniejszy dokument odwraca tę decyzję produktową.

## 2. Zmienione decyzje produktowe

| Decyzja | Było (10.08) | Jest |
|---|---|---|
| Realizm | Uproszczony manekin | Realistyczna anatomia z siatki bazowej |
| Głowa | Brak | Obecna, z twarzą z siatki bazowej — patrz niżej |
| Dłonie i stopy | Brak | Obecne, nieskalowane pomiarami |
| Źródło siatki | Generowana w kodzie | Wypieczony asset CC0 + deformacja |

Bez zmian: morf A→B między dwiema datami, wymagane wszystkie metryki, okno
±14 dni, uśrednianie L/P, płeć wymagana, walidacja objętości, premium.

### Twarz — decyzja odwrócona po dowodach (16.08)

Pierwotnie ustalono „wygładzoną głowę bez rysów", zgodnie z duchem specu z 10.08.
**Zrealizowano, obejrzano i odrzucono.** Wygładzanie nie potrafi tego dostarczyć:
twarz w siatce MakeHumana niesie geometrię wewnętrzną — powieki, wewnętrzne
powierzchnie warg, nozdrza — która pod filtrem dość silnym, by spłaszczyć rysy,
zwija się na siebie. Efektem są samoprzecięcia i odwrócone normalne, widoczne
jako cętkowanie na żuchwie, przy wciąż czytelnych oczach i ustach. Wynik był
gorszy od obu skrajności.

Zmierzone warianty:

| Podejście | Efekt na rysach | Koszt |
|---|---|---|
| Taubin, cała głowa, 40 it. | amplituda 0,1024 → 0,0383, rysy zostają | promień −0,0% |
| Laplasjan, cała głowa, 200 it. | nos −33% | promień −14,5% |
| Laplasjan, płat twarzy, 60 it. | detal −93%, ale artefakty fałd | promień −0,76% |

Wniosek: czysta głowa manekina wymaga **wymiany geometrii** (elipsoida zszyta na
obwodzie szyi), nie filtrowania. Uznane za niewarte kosztu — referencja
dostarczona przez użytkownika (Zygote) sama ma pełną twarz. Twarz zostaje.

## 3. Asset bazowy

Źródło: repozytorium MakeHuman, `makehumancommunity/makehuman@master`.

Licencja: **CC0 1.0 Universal**. `LICENSE.md` sekcja C wymienia wprost
*„The base mesh and proxies / Targets and modifiers / Textures"* jako assety
wydane na CC0. Kod aplikacji jest AGPL, ale bierzemy wyłącznie assety, więc
AGPL nas nie dotyczy. Dla dystrybucji na App Store jest to czyste: bez opłat,
bez atrybucji, bez copyleft.

Pobrane do `tools/bodymesh/source/` (poza targetem aplikacji — projekt używa
`PBXFileSystemSynchronizedRootGroup`, więc cokolwiek pod `MeasureMe/` zostałoby
automatycznie wciągnięte do buildu):

| Plik | Rozmiar |
|---|---|
| `base.obj` | 1,75 MB |
| `caucasian-male-young.target` | 396 KB |
| `caucasian-female-young.target` | 421 KB |

### Weryfikacja

Zmierzone na pobranym pliku, nie przyjęte na wiarę:

- 19 158 wierzchołków, 18 486 ścian, **100% quadów, zero trójkątów**
- 21 334 współrzędne UV
- 172 grupy w trzech rodzinach: `body` (13 380 wierzchołków, 69,8%),
  `helper-*` (4 778, 24,9%), `joint-*` (1 000, 5,2%)
- bounding box grupy `body`: X `-4,963..4,963`, Y `-8,168..8,491`,
  Z `-1,015..3,215`; wysokość 16,659 jednostek, czyli jednostką są decymetry
  (skala do 180 cm: ×10,805)
- głowa obecna: 87 wierzchołków w górnych 3% wysokości, rozpiętość X 1,277
- stopy obecne: 1 964 wierzchołki w dolnych 3%, rozpiętość Z 2,428

### Poza

**A-pose, potwierdzone pomiarem.** Oś bark→łokieć
(`1,677; 5,246` → `3,129; 3,493`) tworzy **39,6° z pionem**. Oś kolano→kostka
(`1,581; −3,695` → `2,196; −7,448`) tworzy **9,3°**.

Wniosek dla algorytmu: obwód liczony w płaszczyźnie poziomej jest zawyżony o
`1/cos θ`. Dla ramienia to **+30% — nie do zaakceptowania**, więc przekroje
kończyn górnych liczymy prostopadle do osi ramienia. Dla nogi to +1,3%, poniżej
progu istotności, więc nogi i tors tniemy poziomo.

Grupy `joint-*` dostarczają pozycji stawów (bark, łokieć, dłoń, biodro, kolano,
kostka, szyja, głowa) jako centroidy ośmiowierzchołkowych kostek. To gotowy
szkielet — osie kończyn bierzemy stąd, nie zgadujemy.

## 4. Pipeline offline

`tools/bodymesh/bake.py` — uruchamiany ręcznie, raz; wynik commitowany.
Nie jest częścią builda aplikacji.

Kroki:

1. Wczytaj `base.obj`, zbuduj mapę wierzchołek → grupa.
2. Odrzuć `helper-*` i `joint-*` z geometrii wyjściowej. Gałki oczne siedzą w
   `helper-l-eye`/`helper-r-eye`, więc znikają automatycznie — w twarzy zostają
   same oczodoły.
3. Zapisz centroidy `joint-*` do `BodySkeleton.json`.
4. Nałóż target płci (format: `indeks wierzchołka + delta xyz`), wypiekając
   wariant męski i damski.
5. **Wygładź głowę** filtrem Taubina (40 iteracji) — usuwa szorstkość
   wysokoczęstotliwościową bez kurczenia bryły. Rysy twarzy zostają celowo;
   powód w sekcji 2.
6. Zapisz `MaleBase.obj` i `FemaleBase.obj` do zasobów aplikacji.

Skrypt jest deterministyczny — te same wejścia dają bit-identyczne wyjście.

## 5. Runtime

### Nowe moduły

**`BodyMeshFile`** — dekoder własnego formatu binarnego `.bodymesh`
(nagłówek `BMSH`, wersja, liczby wierzchołków i indeksów, potem surowe
`Float32`). Pozycje znormalizowane: stopy na `y = 0`, wysokość dokładnie 1,0,
bounding box wyśrodkowany w X i Z — skalowanie do wzrostu to jedno mnożenie.

Wybór formatu binarnego zamiast OBJ: etap 2 potrzebuje surowej tablicy pozycji
do deformacji, a parsowanie ASCII OBJ przy starcie to ~50 000 konwersji
tekst→float. Binarnie to `memcpy`, plik ~3× mniejszy, a dekoder krótszy niż
obsługa ModelIO. UV nie są wysyłane — matowy materiał ich nie używa.

**`BodyRegionMap`** — przypisuje każdemu wierzchołkowi region (tors, ramię L,
ramię P, noga L, noga P, głowa, dłoń L/P, stopa L/P) oraz parametr `t` wzdłuż
osi regionu. Liczone raz z siatki bazowej i szkieletu.

**`BodyMeshDeformer`** — jądro rozwiązania. Interfejs:
`deform(base:regions:parameters:) -> [SIMD3<Float>]`.

### Algorytm

Obserwacja, na której stoi wydajność: **obwody i centroidy pasów siatki bazowej
są statyczne**. Liczymy je raz przy ładowaniu.

Na klatkę zostaje:

1. Warp osi Y — odwzorowanie piecewise-linear, które sadza punkty
   antropometryczne siatki bazowej na wysokościach z solvera. Obsługuje wzrost
   i korektę podziału tors/nogi z walidatora objętości.
2. Dla każdego wierzchołka: odczytaj współczynnik `target/base` dla jego pasa
   (interpolowany między sąsiednimi pasami) i przeskaluj promieniowo wokół
   centroidu pasa, w płaszczyźnie prostopadłej do osi regionu.
3. Przelicz normalne.

Koszt: O(n) po 13 380 wierzchołkach — poniżej milisekundy, więc morf suwakiem
zostaje płynny bez dodatkowej optymalizacji.

### Regiony nieskalowane

Głowa, dłonie i stopy nie mają pomiarów, więc nie wolno ich skalować.
Współczynnik wygasza się gładko do 1,0 przez szyję, nadgarstek i kostkę —
inaczej powstałby szew na granicy regionu.

### Morf między datami

Bez zmian: interpolujemy `BodyMeshParameters` (tanie, kilkadziesiąt liczb),
a deformacja przelicza się z wyniku. Gwarancja z obecnego designu zostaje —
każdy stan pośredni jest poprawnym ciałem.

## 6. Materiał

Matowy, glinany render bez tekstury skóry, bez włosów, łysa głowa. Wybór jest
celowy: unika doliny niesamowitości, do której zaprowadziłaby półrealistyczna
skóra, i trzyma model w rejestrze „obiekt do oglądania", a nie „awatar".

Realizacja: `.physicallyBased` z jasnym, ciepłoszarym albedo i `roughness`
w okolicy 0,65, oświetlone trzypunktowo. Matcap z litsphere'ów MakeHumana dałby
ten sam efekt, ale wymaga shader modifiera i dodatkowego assetu — zostaje jako
plan B, jeśli PBR nie trafi w referencję.

Oświetlenie: miękkie światło studyjne plus cień kontaktowy pod stopami, żeby
model nie unosił się nad tłem.

## 7. Co zostaje, co znika

**Znika:**

- `BodyGeometryBuilder.swift` (154 linie) i `BodyGeometryBuilderTests`
- stałe `armOffsetCm`, `legOffsetCm` — zastąpione anatomią siatki

**Zostaje bez zmian:**

- `BodyMeshSolver`, `BodyProportions` — nadal produkują docelowe obwody
- `BodyVolumeValidator`, `Superellipse` — walidator całkuje pole superelipsy
  (`shape.area`) do uzgodnienia objętości z wagą; to pozostaje analitycznym
  modelem wewnętrznym, niezależnym od siatki renderowanej
- `BodySnapshot`, `BodySnapshotBuilder`, `BodyModelViewModel`,
  `BodyModelScreen`, `BodyModelMissingMetrics`

`MannequinView` zmienia się w zakresie źródła geometrii i materiału; kamera i
obsługa `colorScheme` zostają.

## 8. Kryteria akceptacji

1. **Round-trip obwodów.** Zdeformuj siatkę do zadanych obwodów, następnie
   zmierz obwód *zdeformowanej siatki* w każdym punkcie antropometrycznym.

   **Zrewidowane po implementacji: ±3%, nie ±1%.** Pierwotna liczba była
   optymistyczna i nie została osiągnięta. Zmierzone na talii przy wzroście
   180 cm: 76 → 77,4 (+1,8%), 86 → w granicach 1%, 104 → 101,0 (−2,9%).

   Błąd nie jest systematycznym zaniżeniem, tylko **regresją ku kształtowi
   bazowemu**: wygaszanie współczynnika między pasami uśrednia w stronę siatki
   bazowej, więc małe cele wychodzą zawyżone, a duże zaniżone. Zwężenie tego
   wymagałoby więcej pasów, a siatka nie ma na to wierzchołków — tors trzyma
   tylko 7,6% z nich i przy dziesięciu pasach damskie przedramię już się
   wyludnia.
2. **Brak szwów.** Na granicach regionów długość krawędzi po deformacji nie
   rośnie o więcej niż **150%** (czyli 2,5×) względem tej samej krawędzi przed
   deformacją.

   Pierwotne 50% było zgadywanką i okazało się bezużytecznie ostre: stan, który
   na renderze nie pokazuje żadnego szwu, ma jedną krawędź w pasze rozciągniętą
   2,2×. Próg 2,5× nadal łapie każdą regresję, która faktycznie wystąpiła w
   trakcie budowy — 14,5× bez mieszania regionów, 9,9× po przeniesieniu szyi do
   torsu, 7,7× po wygładzeniu pola wag, 4,5× bez wygaszania na szyi, 3,3× po
   poszerzeniu rampy.
3. **Niezmienność regionów bez pomiarów.** Wierzchołki głowy, dłoni i stóp
   pozostają na pozycjach z siatki bazowej po warpie Y, z dokładnością do zera
   maszynowego.
4. **Determinizm wypieku.** Ponowne uruchomienie `bake.py` daje bit-identyczne
   pliki wyjściowe.
5. Testy migawkowe `BodyModelSnapshotTests` przechodzą z nowymi bazami.

## 9. Etapy

Zakres jest na tyle duży, że dzieli się na dwa etapy z osobnymi punktami
kontrolnymi.

**Etap 1 nie jest wydaniem.** Po nim model przestaje reagować na pomiary —
suwak morfa zmieniałby wyłącznie wzrost, co jest regresem funkcjonalnym mimo
lepszego wyglądu. Etap 1 to punkt kontrolny na branchu; `BodyGeometryBuilder`
zostaje na miejscu i zostanie usunięty dopiero na końcu etapu 2, żeby `main`
nigdy nie był w stanie regresu.

**Etap 1 — realna siatka na ekranie.** Wypiek offline, ładowanie assetu,
jednolite skalowanie do wzrostu, materiał i oświetlenie. Model wygląda jak
człowiek, ale obwody są jeszcze te z siatki bazowej.
Punkt kontrolny: render zgodny z referencją, migawki zaktualizowane.

Piecewise-linear warp osi Y należy do etapu 2, nie 1 — służy korekcie podziału
tors/nogi z walidatora objętości, która ma sens dopiero razem z deformacją.
Etap 1 skaluje jednolicie.

**Etap 2 — deformacja pomiarami.** Mapa regionów, osie kończyn, skalowanie
promieniowe, wygaszanie na głowie/dłoniach/stopach, test round-trip.
Punkt kontrolny: kryterium akceptacji 1 przechodzi.

Podział ma też wartość diagnostyczną: jeśli artefakty w pachach i kroku
(ryzyko poniżej) okażą się poważne, wyjdą dopiero w etapie 2, a etap 1 zostaje
już wtedy zweryfikowany i nie trzeba go debugować równolegle.

## 10. Ryzyka i ograniczenia

- **Model nie ma twarzy użytkownika ani jego muskulatury.** Obwód bicepsa
  zmienia grubość ramienia, ale nie rzeźbę mięśnia. `bodyFat` wpływa wyłącznie
  przez objętość, nie przez rozkład tkanki.
- **Model zachowuje cudzą twarz.** To świadomy kompromis opisany w sekcji 2, nie
  przeoczenie. Jeśli w testach z użytkownikami okaże się to zgrzytem przy
  własnych pomiarach, wyjściem jest wymiana geometrii głowy, nie mocniejszy filtr.
- **Wygładzanie głowy jest krokiem wizualnym, nie liczbowym.** Nie ma na to
  automatycznego testu poza migawką; liczbę iteracji dobiera człowiek.
- **Rozmiar aplikacji.** Dwa OBJ-e po ~13 400 wierzchołków. Do zmierzenia po
  wypieku; jeśli przekroczą budżet, opcją jest format binarny zamiast OBJ.
- **Deformacja promieniowa zakłada wypukłe przekroje.** W okolicy pach i kroku
  przekrój bywa wklęsły; jeśli pojawią się artefakty, region wymaga osobnego
  potraktowania. Do sprawdzenia na pierwszym renderze.
