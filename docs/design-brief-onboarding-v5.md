# Prompt: projekt GUI onboardingu v5 dla MeasureMe

Jesteś senior product designerem iOS. Zaprojektuj GUI nowego flow onboardingu (v5) i trzech elementów dashboardu dla aplikacji MeasureMe. Pracujesz w istniejącym design systemie — nie wymyślaj nowego języka wizualnego.

## Kontekst produktu

- MeasureMe: aplikacja iOS (SwiftUI, iOS 17.2+) do śledzenia pomiarów ciała — 18 metryk (waga, obwody, % tkanki tłuszczowej), zdjęcia progresowe, integracja Apple Health, AI insights liczone na urządzeniu. Freemium z planem Premium.
- Persona: osoba zaczynająca redukcję, budowę masy albo rekompozycję. Instaluje aplikację często „w biegu", bez miarki pod ręką. Zna swoją wagę z głowy, nie zna obwodów.
- Cel biznesowy redesignu: (1) podnieść odsetek nowych użytkowników zapisujących pierwszy pomiar w onboardingu (obecnie ~19%), (2) podnieść odsetek wracających na drugi pomiar (obecnie ~13%). Aha-moment produktu to pierwszy trend na wykresie, który pojawia się dopiero przy drugim pomiarze — około tygodnia po instalacji. Onboarding musi więc kończyć się „kontraktem na powrót", nie tylko zebraniem danych.
- Maskotka: „Miara" — jedna postać w 10 pozach (welcome, goals, reminder, streak, celebration, success, ai, summary, thumbs, settings). Używaj oszczędnie i semantycznie: jedna poza na ekran, tylko tam, gdzie niesie emocję.

## Design system — twarde ograniczenia

- Akcent: amber `#FCA311` (CTA, podświetlenia, wybrane stany). Tekst na akcencie: `#141413` (ciemny, nie biały).
- Tła dark mode: ink `#050816`, midnight `#0C1329`, navy `#14213D`. Tła light mode: paper `#F3F7FD`. Wszystkie ekrany projektuj w obu trybach — kolory ról są dynamiczne.
- Kolory semantyczne: danger `#EF4444`, teal `#29C7B8`, emerald `#2DD881` (pozytywne trendy), rose `#FF6B8A`.
- Karty: styl „glass" z trzema poziomami głębi — floating (hero ekranu), elevated (główna treść/formularze), base (wiersze list, karty zagnieżdżone). Cienie miękkie, rozproszone.
- Promienie narożników: skala 10/12/14/16/18/20/22/24 (sm→xl). Karty zwykle 16–18, przyciski 14.
- Spacing: skala 4/8/12/14/16/24/32/40.
- Typografia: SF Pro; nagłówki display i wartości liczbowe w wariancie rounded, bold; liczby z monospacedDigit. Hierarchia: duży nagłówek ekranu, 1 zdanie podtytułu, treść.
- Kontrolki: primary CTA = pełna szerokość, min. wysokość 52 pt, wypełnienie akcentem; secondary = obrys/wypełnienie subtelne; segmenty = „glass segmented"; małe akcje inline = kapsuły.
- Wzorce nawigacji onboardingu: kropki postępu na górze (aktywna = wydłużona kapsuła w akcencie), okrągły back-chevron po lewej, tekstowy link „Pomiń na razie" po prawej, jeden primary CTA przyklejony do dołu z gradientowym tłem pod spodem.
- Dostępność: Dynamic Type, cele dotykowe min. 44 pt, warianty dla reduce motion, kontrast WCAG AA w obu trybach.

## Zadanie

Zaprojektuj 6 ekranów onboardingu + 3 elementy dashboardu. Dla każdego: hi-fi mockup w proporcji iPhone (390×844) w wersji light i dark, stany (default / błąd / loading, gdzie dotyczy) oraz 2–3 zdania uzasadnienia decyzji.

### Ekran 1 — Welcome
Cel: dowód wartości w 3 sekundy, zero czytania. Grafika before/after zależna od celu (assety istnieją w aplikacji), nagłówek wartości (≤6 słów), jedno krótkie zdanie od Miary (poza welcome, max 1 linia), CTA „Zaczynamy". Bez pól, bez wyborów.

### Ekran 2 — Cel
Trzy karty celów: Schudnąć / Budować mięśnie / Rekompozycja, każda z 1-liniowym opisem korzyści. Tap = wybór + automatyczne przejście dalej (bez osobnego „Dalej"). Po wyborze pojawia się banner „Zaczniemy od: [chipy metryk]". Bez pola imienia — imię nie istnieje w tym flow.

### Ekran 3 — Punkt startowy (najwyższe ryzyko produktowe — daj 2 warianty)
Waga jako hero input: bardzo duże pole liczbowe, klawiatura numeryczna otwarta od razu, przełącznik/etykieta jednostki kg/lb. Pozostałe metryki celu (np. pas, klatka) zwinięte pod „Dodaj więcej (opcjonalnie)". Drugorzędna ścieżka wyjścia zamiast zwykłego skipa: „Nie mam jak się teraz zmierzyć → przypomnij mi wieczorem". Zaprojektuj też stan błędu walidacji. CTA „Zapisz punkt startowy".

### Ekran 4 — Rytm check-inów (nowy ekran, kluczowy dla retencji — daj 2 warianty)
Pytanie: „Kiedy robisz cotygodniowy check-in?". Wybór dnia tygodnia (chipy) + godziny, default: niedziela 9:00. Pod spodem wyjaśnienie wartości jednym zdaniem („Przypomnę Ci — a Ty zobaczysz swój pierwszy trend"). Pre-prompt przed systemową zgodą na notyfikacje: pokaż stan przed zgodą i po zgodzie (potwierdzenie z pozą reminder Miary).

### Ekran 5 — Boostery
Dwie równorzędne karty: „Zdjęcie startowe" (prywatne, opcjonalne, wskazówka o świetle i kadrze) i „Połącz Apple Health" (import historii, automatyczna synchronizacja). Obie z mikrocopy prywatności — „zostaje na Twoim urządzeniu". Stany: nic nie zrobione / jedno / oba (checkmarki).

### Ekran 6 — Twój plan
Podsumowanie-kontrakt: wybrany cel, chipy metryk startowych, pierwsza kropka na mini-wykresie (oś czasu sugerująca przyszły trend), duża data następnego check-inu, Miara w pozie celebration. CTA „Pokaż dashboard".

### Dashboard A — Checklista startu
Karta na górze dashboardu z 3–4 zadaniami: Punkt startowy / Zdjęcie startowe / Przypomnienie / Połącz Health. Checkmarki, pasek lub pierścień postępu („2 z 4"), każdy wiersz tapowalny i prowadzący wprost do funkcji. Zadania ukończone w onboardingu są odhaczone od startu. Zaprojektuj stan częściowo ukończony i moment ukończenia całości.

### Dashboard B — Hero „pierwsza kropka"
Stan dashboardu po jednym pomiarze: zapisana wartość + komunikat z odliczaniem do następnego check-inu („Wróć w niedzielę — zobaczysz pierwszy trend") zamiast pustego wykresu.

### Dashboard C — Celebracja drugiego pomiaru
Moment pierwszego trendu: delta z kolorem semantycznym, strzałka kierunku, Miara w pozie celebration. Zaproponuj 2 warianty intensywności: subtelny toast vs karta hero — z rekomendacją.

## Zasady copy

- Wszystkie teksty w PL i EN, sentence case.
- Ton: wspierający, konkretny, bez oceniania — „bez dramy wagi". Nagłówek ≤6 słów, body ≤2 zdania.
- Nie obiecuj efektów zdrowotnych. Prywatność komunikuj wprost: „Twoje pomiary i zdjęcia zostają na urządzeniu".

## Czego nie zmieniać

- Mocne copy prywatnościowe przy Health i zdjęciach (działa).
- Wzorzec banneru „Zaczniemy od…" po wyborze celu.
- Maskotka Miara pozostaje elementem brandu — można korygować ekspozycję, nie usuwać.

## Format odpowiedzi

1. Mockupy wszystkich ekranów (light + dark), 390×844.
2. Po 2 warianty ekranów 3 i 4 z rekomendacją, który wdrożyć.
3. Lista decyzji projektowych i ryzyk (max 10 punktów).
4. Lista pytań otwartych, jeśli czegoś brakuje do podjęcia decyzji.
