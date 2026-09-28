# Kolejny pełny przegląd — zlecenie 27 września 2026

Status: czytanie autorskiego kodu, narzędzi i testów zakończone
28 września 2026. Audyt nastąpił po dostępnych próbach MCP bieżącego planu
i usunięciu sond. Jawne luki, w tym powtórne wejście przez widget poza
pierwszym planem, opisuje `CURRENT_FIXES_IMPLEMENTATION.md`.
Nie zastępuje ani nie powtarza od początku wcześniejszych ukończonych porządków.
Prywatny rejestr: `diagnostics/full-audit-20260928/INVENTORY.json`,
`REVIEWED.json` oraz `FINDINGS.md` w nadrzędnym katalogu roboczym.

Użytkownik zlecił następnie pełne, szczegółowe czytanie projektu: plik po
pliku, klasy, metody i poszczególne linie. Szukać błędów, martwego kodu,
nieistniejących zależności/API, zbędnych obejść, duplikacji, nieaktualnych
gałęzi i niepotrzebnej komplikacji. Przejrzeć również testy i narzędzia,
odróżniając kod autorski od generowanych zasobów i danych zewnętrznych.

Prowadzić rejestr pokrycia przeglądu. Dla ustaleń podać konkretne miejsce,
warunki wystąpienia, dowód, wpływ i zakres proponowanej poprawki. Oddzielać
błąd funkcjonalny od utrzymania kodu oraz od hipotezy. Wątpliwe zachowania
sprawdzać celowanymi testami i na rzeczywistych kopiach ELTEN-a; użytkownik
zatwierdził takie próby. Korzystać z własnych stołów i kont testowych,
sprzątać ich dane i sondy. Nie utożsamiać handlerów UI, odsłuchu i fizycznej
klawiatury ani jednego komputera z wieloma niezależnymi łączami.

Nie deklarować ukończenia na podstawie samych wyszukiwań tekstu. Raport
ma uczciwie wskazywać pozostałe luki. Zlecenie audytu nie oznacza automatycznej
zgody na zmianę reguł gier, szerokie przebudowy ani publikację wydania.

## Wynik przeglądu

Przeczytano wszystkie 234 pliki autorskiego kodu wykonawczego (70 205 linii),
82 narzędzia (11 306 linii), 626 plików testów i pomocników (68 558 linii)
oraz trzy pliki konfiguracji. Są to liczby przeczytanych źródeł, NIE liczby
wykonanych testów. Wybór bieżącej dokumentacji i zewnętrzny algorytm Unicode
przeczytano osobno. Wszystkie historyczne dokumenty i generowane tabele,
słowniki, tłumaczenia oraz bazy pytań nie były nowym audytem linia po linii
ani audytem merytorycznym treści. Generatory i odbiorcy tych danych są objęte
przeglądem kodu. Rejestr zakresów i sum plików pozostaje w raporcie prywatnym.

### Ustalenia wymagające uzgodnienia

- D01: nieaktualny zakres Ctrl+J w architekturze i lista 29 zamiast 32 gier.
- D02: puste potwierdzenia bota zapisywane podczas zwykłego odświeżenia.
- D03: drugi scheduler botów w GameScreen, nieużywany przez bieżące gry.
- D04: następca gospodarza może być wybrany z obsady wcześniejszej partii.
- D05: błąd odczytu po zamrożeniu zapisu może zostawić partię wstrzymaną.
- D06: przejście z zaproszenia omija ochronę wyjścia z prywatnej fazy gry.
- D07: późny obserwator Ponga buforuje ruchy bez początku wymiany i po
  przepełnieniu wywołuje niepotrzebne ponowne połączenie.
- D08: poddanie się przeciwnika może zamknąć nierozstrzygniętą próbę Krowy.
- D09: Farkle odrzuca pięciokościowy strit z dodatkową punktującą kością.
- D10: Państwa-miasta po pierwszym cyklu nie resetują wykorzystanych liter.
- D11: niepoprawny tekst ruchu Tysiąca może przerwać odtwarzanie historii.
- D12: pięć klas raportów treningu Spades nadal trafia do runtime.
- D14: generator Taboo może zapisać tylko jeden język przed odrzuceniem danych.
- U01: Ayoayo wymaga jawnej decyzji o cyklu siania; samo usunięcie obecnego
  ograniczenia 201 etapów zapętliłoby osiągalny ruch.

Nie wdrożono tych zmian podczas audytu. Nie wszystkie są błędami rozgrywki;
raport rozróżnia usterki, utrzymywalność i decyzje dotyczące zasad. Każdy
punkt ma minimalną propozycję zmiany oraz dowód ze wskazaniem rodzaju próby.

### Poprawki samych testów

Użytkownik zezwolił na ich samodzielne naprawianie. Ukończono D13 oraz
D15–D19: ograniczenie czekania na wyjście procesu testowego, aktualne
kontrakty formularzy, izolację historycznych kontroli quizu, wspólny wybór
źródeł hosta, deterministyczny zegar testu i uszczelnienie asercji UI/audio.
Celowane próby po poprawkach przechodzą; kontrolna mutacja dźwięku jest
odrzucana tam, gdzie wcześniejszy test błędnie ją przepuszczał.

Nie wykonano pełnego runnera, nie zmieniano aplikacji w celu dopasowania
do starej atrapy i nie pomijano błędów produkcji. Pierwsze niepowodzenia
i osobne ponowienia zachowano. Próby modeli przez MCP nie są przedstawiane
jako żywe mecze. Nie zbudowano paczki ani nie zmieniano wersji/publikacji.

## Wdrożenie po zatwierdzeniu zakresu — 28 września 2026

Użytkownik zatwierdził punkty rozmowy 1–13 z wyłączeniem 5. Punkt 14 również
pozostaje bez zmian. Oznacza to dwanaście wdrożonych pozycji:

1. D05: zapis zachowuje potwierdzenie własnej granicy zamrożenia. Awaria
   późniejszego odczytu pozwala cofnąć tę granicę, ale nie nowszy zapis,
   zamkniętą partię lub operację innego gospodarza.
2. D06: zwykłe wyjście i przyjęcie zaproszenia mają wspólną kontrolę prywatnej
   fazy. Jest sprawdzana przed dołączeniem i ponownie przed opuszczeniem
   starego stołu; późne odrzucenie sprząta tylko nowe członkostwo.
3. D04: następca jest wybierany według kolejności rozpoczęcia partii na stosie,
   nie według losowego identyfikatora. Nadal może nim zostać obserwator,
   jeśli nie ma innego grającego człowieka.
4. D07: późny zdalny obserwator Ponga korzysta z autorytatywnego obrazu gry,
   zamiast bez końca buforować odbicia bez początku wymiany. Zachowano
   uprawnienia, deduplikację punktów i ponaglenia.
5. D09 (punkt rozmowy 6): pięciokościowy strit w Farkle może obejmować
   dodatkową punktującą kość; wybierane jest poprawne najlepsze grupowanie.
6. D10 (7): Państwa-miasta zaczynają nową pulę liter po wyczerpaniu alfabetu.
7. D11 (8): niepoprawny zapis zagrania w Tysiącu jest odrzucany bez mutacji
   stanu i bez zatrzymania odtwarzania kolejnych prawidłowych ruchów.
8. D14 (9): generator Taboo waliduje oba języki przed zapisem; zastępowanie
   trzech plików ma odwracanie częściowego zapisu i zachowanie plików
   ratunkowych, jeśli samo odwracanie zawiedzie. Nie jest to transakcja
   odporna na przerwanie zasilania.
9. D03 (10): usunięto nieużywanego wykonawcę botów z ekranu. Pozostały wspólny
   runner gier turowych, osobne pętle realtime i automatyczne zapisy punktów.
10. D12 (11): pięć definicji treningowych Spades przeniesiono poza runtime.
    Polityka gry, wagi i wybory strategii nie zostały przepisane.
11. D02 (12): usunięto puste potwierdzenia bota wraz z martwą ścieżką.
12. D01 (13): poprawiono bieżącą dokumentację Ctrl+J, liczbę gier i kontrakt
    wykonawcy dla autorów nowych gier.

Wyłączenia: D08/Krowa (punkt rozmowy 5) i U01/Ayoayo (14). Nie zmieniono ich
zasad. Dawna lista ustaleń powyżej jest historycznym wynikiem audytu,
nie aktualną listą całkowicie niewdrożonych poprawek.

Weryfikacja i ograniczenia są w prywatnym raporcie
`diagnostics/full-audit-fixes-20260928/README.md` w katalogu roboczym.
Wiele przebiegów celowanych, nie cały runner: 66 unikalnych skryptów ma
ostatni wynik poprawny. Dzieci agregatu liczone raz; pierwsze niepowodzenia
i poprawki atrap zachowano. Sam agregat Audio Balla nie był powtarzany:
ponowiono tylko jego wcześniej nieudane dziecko, także w trybie binarnym.
Próby żywych kont obejmują UNO, Statki, Ponga, Spades, Farkle, Tysiąc,
Państwa-miasta oraz Audio Balla. To rzeczywiste API i handlery kontrolek
na jednym komputerze, nie fizyczna klawiatura, odsłuch ani różne łącza.
Narzędzia generujące i dokumentacja sprawdzane lokalnie, nie udawane mecze.
Bez nowej paczki, podpisu, wersji, changelogu i publikacji.
