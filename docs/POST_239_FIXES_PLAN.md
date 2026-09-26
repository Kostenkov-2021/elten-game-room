# Kolejne poprawki po buildzie 239

Stan: 26 września 2026. Cały poniższy plan wdrożono w źródłach.
Opisy „do wdrożenia” w dalszych punktach dokumentują pierwotny przegląd,
nie oznaczają pozostawionych zadań. Podsumowanie wykonania poniżej.
Osobno zatwierdzono utworzenie trzech tabel statystyk na serwerze oraz
zakres zbierania dokładnie taki jak w PR #21. Status tej operacji poniżej.
Po wdrożeniu uzupełnić changelog z pominięciem zmiany Ctrl+M oraz ponownie
zbudować i podpisać build 239 bez zmiany numeru wersji. Nie instalować
ani nie publikować paczki/GitHuba bez osobnego polecenia.

### Wykonanie

- Jeden proces ma jednego właściciela interfejsu; kolejne uruchomienie
  używa natywnego przełączenia wątku ELTEN-a. Konkretne wejścia widgetu
  i powiadomień są przekazywane do istniejących ścieżek dopiero na
  granicy głównego formularza, nie z wnętrza aktywnego dialogu.
- Ctrl+M przekazuje gospodarza zaznaczonemu człowiekowi wyłącznie na
  liście osób. Dynamiczna pomoc respektuje wybór i uprawnienia; Ctrl+X
  pozostaje wycinaniem w polach tekstowych. Tej zmiany Ctrl+M nie dodano
  jako nowego punktu changelogu.
- PR #21 i #22 włączone lokalnie. Statystyki odkładają małe kopie danych
  w pamięci, worker wykonuje trwały zapis i wysyłkę. Po odtworzeniu tej
  samej partii inna data ukończenia nie tworzy fałszywego konfliktu.
  Rzeczywiste konflikty nadal odrzucane; przepełniona kolejka może się
  opróżnić. Tarcza Arcade jest wspólna dla drużyny deblowej.
- Trzy tabele statystyk istnieją na serwerze. `room_presence` dodatkowo
  pozwala usuwać własne stare raporty: najwyżej 64 rekordy na publikację,
  starsze niż dwa bieżące przedziały czasu, z ponowną kontrolą aktualności
  i własności. Odczyt już wcześniej pomijał raporty wygasłe. Nie jest to
  serwerowy harmonogram sprzątania: dla nieaktywnego konta pozostałość
  może czekać do kolejnej publikacji. Nie usuwamy cudzych raportów ani
  historycznych statystyk. Osiem wcześniejszych tabel, ochrona i quota
  16 MiB pozostały bez zmian.
- Chińczyk ma domyślne wyjście po 1 dla nowych stołów. Dawny zapis bez
  tej opcji zachowuje stare zasady. Jedynka nie daje dodatkowego rzutu.
  Odczyty są krótsze; C podaje mapę kolorów, Ctrl+C przełącza prezentację.
  Kolory miejsc: czerwony, niebieski, żółty, zielony.
- Prezentacja Chińczyka oraz orientacja Szachów/Warcabów i współrzędne
  Warcabów zapisują się lokalnie. Orientacja jest względna wobec własnego
  miejsca. Nie zapisujemy zaznaczeń, kursora, rąk ani szkiców ruchów.
- Dodano wszystkie 22 wskazane imiona. Starsze identyfikatory nazw
  i angielska lista zachowane.
- Przeczytano cały wskazany wątek quizu. Korekty 13 pytań i potwierdzenie
  kolejnego opisuje `QUIZ_FORUM_CORRECTIONS_239.md`, a dokładne zmiany
  dokumentuje JSON obok. Liczebność, ID i poprawne odpowiedzi zachowane.

Weryfikacja jest celowana i lokalna, z natywnymi kontrolkami/API hosta
w testach oraz odczytem i podglądem rzeczywistego schematu serwera.
Nie jest to nowa seria żywych partii ani próba zwykłego zbierania danych
z dwóch kont. Nie przełączano trybu deweloperskiego i nie wczytywano
zmian do uruchomionych klientów. Nie wykonano pełnego runnera.

### Paczka i wynik kontroli

Podpisana ponownie wersja 2.0.4/build 239: 24 296 553 bajty, SHA-256
`a4582c33925af6cb1cfcf00115201305e5d82f8415a472d516e3db9f9d3581b8`.
Plik w `artifacts/game-room/testing/ELTEN-Game-Room-build-239-signed.eltsetup`
w głównym katalogu roboczym. Podpis autora papierek, zgodność obu manifestów,
wszystkich 397 plików wykonawczych (240 Ruby) i 143 wymaganych dźwięków
potwierdzone. Ostatnie wyniki 61 unikalnych skryptów celowanych: PASS;
siedem kontroli gotowej paczki: PASS. To kilka przebiegów celowanych,
nie pełny runner ani testy żywych partii. Zachowano pierwotne niepowodzenia
w prywatnych raportach `diagnostics/post239-*.json`; dotyczyły również
aktualizacji dawnych oczekiwań, przeniesionego walidatora i pomocników.
Kontrole binarne obejmują opcje, nowe planszówki, statystyki, wszystkie
gry, quiz v5, PL/EN/fallback oraz przeładowanie starej paczki 238 na nową.
Nie instalowano i nie opublikowano źródeł ani paczki.

## 1. Ponowne uruchomienie wraca do aktywnego Game Roomu

Uzgodniony kierunek: jedno aktywne okno Game Roomu w jednym procesie
ELTEN-a. Zwykłe kolejne uruchomienie odsłania istniejące okno, zamiast
tworzyć drugą niezależną instancję interfejsu.

Najważniejsze wymaganie użytkownika: poprawka ma dotykać możliwie małej
części programu. Jedno wspólne zabezpieczenie wejścia i cyklu życia,
bez osobnych reguł dla każdej gry, rodzaju stołu lub sposobu zapraszania.
Różne wejścia (Programy, widget, powiadomienie) mogą wymagać podłączenia
do tego mechanizmu, ale nie kopiowania kontroli członkostwa.

- Zapamiętać aktywną instancję i jej okno/wątek. Przykrycie wiadomościami,
  forum albo konferencją nie oznacza zamknięcia. Sam działający widget
  i jego odczyt listy stołów nie rezerwują aktywnego okna Game Roomu.
- Przy zwykłym ponownym uruchomieniu zachować aktualny formularz, fokus,
  szkic czatu, zaznaczenia i bieżącą partię; nie odbudowywać ekranu,
  nie dołączać ponownie do stołu i nie zakładać nowego połączenia.
- Wejście z konkretną czynnością przekazać istniejącej instancji do
  dotychczasowej obsługi, w jej właściwym kontekście UI. Nie wykonywać
  równolegle drugiej pętli interfejsu ani wymuszać przerwania modalnego
  formularza. Samo przeniesienie okna nie przyjmuje zaproszenia.
- Zachować istniejące zabezpieczenia `current_table_for`, tworzenia
  i dołączania oraz pytanie o opuszczenie obecnego stołu przy przyjęciu
  zaproszenia. Sprzątanie powiadomień i przekazywanie gospodarza nadal
  należą do dotychczasowej ścieżki, nie do nowego zabezpieczenia.
- Zwolnić oznaczenie przy rzeczywistym zamknięciu lub błędzie właściciela
  okna. Obsłużyć szybkie podwójne uruchomienie oraz nieaktualną referencję.
  Zakończenie odrzuconego uruchomienia nie może posprzątać zasobów,
  dźwięków ani formularza nadal działającej instancji.
- Zakres jest lokalny dla procesu ELTEN-a, nie dla całego konta lub
  komputera. Osobne kopie testowe pozostają niezależne.

Nie zmieniać transportu, reguł gier ani odświeżania partii. Nie dodawać
serwerowego zakazu wielu stołów na konto, opcji otwierania drugiego okna
ani naprawy zamykania procesu ELTEN-a przy okazji. Zniknięcie stołów po
zakończeniu starego procesu nie ustala jeszcze przyczyny jego pozostania.

### Korekta po próbach natywnego cyklu uruchomienia

Jedna instancja interfejsu nie wystarczała do utrzymania czystego menu Okna:
ELTEN dopisywał już zakończony, przekierowany wątek do swojej listy podczas
przełączania. Poprawka oznacza wyłącznie takie własne uruchomienia i usuwa
z listy tylko zakończone oznaczone wątki, na kolejnym aktywnym odświeżeniu
własnego formularza, również modalnego. Nie zabija wątków ani nie usuwa
cudzych okien. Nie zmienia transportu, partii ani odpowiedzi „Nie”.

Pięć celowanych skryptów zaliczonych: single_instance, single_instance_native,
parallel_scene_events, parallel_scene_native i game_background_native_input.
Nowy test używa natywnego insert_scene, wykonania i przełączania wątków;
zastępuje jedynie klatkę OS/UI. Sześć kolejnych natywnych uruchomień w żywej
głównej kopii również wróciło do tego samego formularza bez martwych wpisów;
zachowano fokus, szkic oraz ID sesji i zaakceptowanych ruchów. To nie jest
pełna regresja ani zakończenie wcześniej przerwanych prób wszystkich wejść.
Poprawione metody pozostawiono w pamięci obu klientów, bez restartu,
instalacji, paczki lub publikacji. Dowody w prywatnym katalogu
diagnostics/single-instance-live-239, plik LAUNCH-CLEANUP.md.

## 2. Chińczyk — krótszy przegląd pozycji

Użytkownik chce odczytu w formie „papierek, tor 5”, „peterman, tor 10”,
bez słowa „pionek” i jego numeru, z nickiem przed pozycją.

Użytkownik rozszerzył zakres na wszystkie odczyty i skróty gry, nie tylko
Shift+V, V oraz P. Pod Shift+V lista wszystkich pionków
(`Ludo#all_pawn_browse_choices`) dziś czyta pozycję, właściciela i numer
pionka; po zmianie najpierw właściciel, potem pozycja, bez numeru pionka.
Pod V (przegląd własnych pionków) i P (odczyt własnych niezakończonych
pozycji, także w bazie) zastosować tę samą zasadę skróconego opisu.
Objąć nią także Shift+P i cyfry 1–4. Zachować dotychczasowy zakres
informacji każdego skrótu; usuwać numery identyfikujące pionki, nie numery
pól, wyniki kości ani liczebność pionków w bazie lub na mecie.

Odwrócenie dotyczy kolejności informacji w etykiecie, nie kierunku
sortowania planszy. Pod Shift+V zachować obecny porządek rosnących numerów
wspólnego toru, następnie tory domowe, bazy i metę. Nie scalać ani nie
usuwać wpisów pionków stojących na tym samym polu.

Nie usuwać na tej podstawie identyfikatorów pionków z modelu, zdarzeń,
zapisów ani sterowania ruchem. To zmiana prezentacji, nie legalnych ruchów,
kolejności uczestników ani znaczenia poszczególnych skrótów.

### Ctrl+C — przełączanie prezentacji; C — przypisanie kolorów

Zatwierdzone przez użytkownika do planu:

- Ctrl+C przełącza lokalny sposób prezentacji „Nazwy graczy” / „Kolory”,
  podobnie do filtra prezentacji planszy. Krótko potwierdzić wybrany tryb,
  bez zmiany fokusu, kursora, ruchu lub ponownego odczytywania całej planszy.
  Domyślnie pozostawić nazwy. Przykłady tego samego miejsca:
  „papierek, tor 5” albo „czerwony, tor 5”.
- C odczytuje przypisanie kolorów do wszystkich graczy, np. „papierek,
  czerwony; peterman, niebieski”. Działa również dla obserwatora i w obu
  trybach podaje nick oraz kolor, aby można było sprawdzić powiązanie.
- Wybrana prezentacja obowiązuje we wszystkich skrótach informacyjnych
  Chińczyka, również V, Shift+V, P, Shift+P, cyfrach 1–4 oraz odczytach
  rzutu, tury i wyników, tam gdzie występuje nazwa gracza. Wspólny opis
  właściciela zastępuje osobne wyjątki przy każdym klawiszu.
- Cyfry zachowują obecne przypisanie: 1 oznacza własne pionki, kolejne
  następnych graczy; dla obserwatora zaczynają od pierwszego miejsca.
  Przełączenie prezentacji nie zmienia tego, czyje pozycje odczytuje cyfra.
- Jest to lokalna preferencja gracza lub obserwatora. Nie zmienia odczytu
  innych osób, zasad stołu ani tożsamości autorów wiadomości i zdarzeń.
  Nie przepisywać zapisanej historii ani czatu na kolory.
- C i Ctrl+C są skrótami pola gry. W czacie zachować wpisywanie litery C,
  a w polach tekstowych, w tym historii, zwykłe kopiowanie Ctrl+C.
- Dopisać skróty do wspólnej pomocy F1 i zasad sterowania, po polsku
  i angielsku, przez istniejące definicje skrótów.

Kolor powinien odpowiadać stałemu miejscu na planszy i mieć takie samo
znaczenie dla graczy i obserwatorów. Przy zastępstwie osoby pozostaje
z miejscem; C podaje aktualną obsadę. Konkretna kolejność kolorów pozostaje
do doprecyzowania; obecny kod Chińczyka nie definiuje kolorów. Zapamiętywanie
preferencji między stołami i uruchomieniami jest już zatwierdzone w punkcie 7.
Użytkownik wybrał przełącznik Ctrl+C, więc nie dodawać przy okazji osobnego
formularza ustawień.

## 3. Ctrl+M na wybranej osobie i zgodność pomocy z zakresem skrótów

Ostateczna decyzja użytkownika: Ctrl+M ma działać tak jak lokalny skrót
Ctrl+Shift+R — wyłącznie na liście użytkowników, na zaznaczonej osobie.
Naciśnięcie przekazuje jej gospodarza bez dodatkowej listy wyboru.
To świadoma zmiana dotychczasowego zachowania globalnego, nie samo
ukrycie wpisu w pomocy. Dotyczy wspólnego interfejsu wszystkich gier,
nie tylko Chińczyka, od którego zaczęło się zgłoszenie.

- Usunąć globalne przypisanie Ctrl+M i globalną pozycję wyboru gospodarza.
  Dopiąć skrót do istniejącej pozycji przekazania gospodarza na liście
  użytkowników; przekazywać tożsamość zaznaczonej osoby, nie indeks wiersza.
- Nie uruchamiać dodatkowego wyboru osoby, gdy fokus jest poza listą,
  nie ma zaznaczenia albo wybrana osoba nie jest dopuszczalna.
- Zachować obecne uprawnienia: polecenie wykonuje aktualny gospodarz,
  odbiorcą może być inny obecny człowiek, także obserwator. Nie przekazywać
  gospodarza botowi, sobie lub osobie, która już opuściła stół.
- Użyć dotychczasowej ścieżki `change_table_control` i transportu.
  Zachować kontrolę aktualności, ograniczenia prywatnych faz, publikację
  zmiany i odświeżenie u uczestników. Przed zapisem ponownie sprawdzić
  gospodarza i wybraną osobę; aktualizacja listy nie może zmienić odbiorcy.
- Pomoc Ctrl+M ma występować tylko na liście użytkowników i odpowiadać
  dostępności akcji. Nie pokazywać jej na polu gry, czacie ani historii.
  Dopasować opis do przekazania zaznaczonej osobie, nie otwierania wyboru.
  Ctrl+Shift+R zachowuje dotychczasową funkcję zastępowania gracza.

Osobna rozbieżność potwierdzona w odczycie źródeł: `add_context_help`
kopiuje wspólne opisy na wszystkie pola oprócz przycisku powrotu. Dla
Ctrl+X menu usuwa skrót zmiany ustawień przy fokusie w EditBox, lecz opis
nadal może być obecny w F1. W czacie Ctrl+X ma pozostać wycinaniem.

Wspólny opis pomocy powinien respektować ten sam zakres pola, skrót
i dostępność co faktyczna obsługa. Zachować rozdzielenie skrótów całego
stołu od działań na wybranym użytkowniku, bez wyjątków per gra.
Uwzględnić zmianę fokusu, wybranej osoby, gospodarza i fazy gry;
nie pozostawiać starych wpisów po utracie dostępności. Skróty
kopiowania/wycinania w polach tekstowych pozostają natywne.

Przy wdrożeniu sprawdzić celowanie Ctrl+M i jego pomoc w poczekalni oraz
partii: wybrany gracz, obserwator, bot, własna osoba, brak zaznaczenia,
odejście odbiorcy, zmiana gospodarza i przestawienie listy przed zapisem.
Potwierdzić brak akcji/pomocy poza listą oraz brak dodatkowego wyboru,
a także zachowanie istniejących ograniczeń i Ctrl+Shift+R. Zaktualizować
testy oczekujące dawnej globalnej deklaracji Ctrl+M. Na tym etapie
zmieniono tylko plan; kod i testy nie zostały zmienione ani uruchomione.

## 4. PR #21 — statystyki i bieżąca aktywność stołów

Przejrzany PR balteama/budyn1211:
https://github.com/papierek1997/elten-game-room/pull/21
Wersja: `842b1ee20f5c66cc1eb3013be6b93757b23ef8ae`, baza `0159ec3`.
To kandydat do włączenia po uzgodnieniu poniższych poprawek, nie dokonana
integracja ani zgoda na zmianę serwera.

Zakres autora do zachowania:

- „Statystyki” poniżej rankingów: odwiedzający, grające konta, rozpoczęte
  i ukończone partie, podział na gry i grę z ludźmi/botami/solo, okresy
  dzienne, ostatnie 7/30/365 dni, lata i cały zebrany okres.
- Ctrl+W z listy głównego menu: liczba publicznych/prywatnych stołów
  i suma członkostw ludzi. Obserwatorzy są liczeni, boty nie. To nie
  liczba wszystkich osób online ani unikalnych ludzi w całym ELTEN-ie.
- Tożsamość statystyczna partii zachowana w zapisie/odtworzeniu; rewanż
  dostaje nową. Nie dopisywać fikcyjnych danych do starych partii.
- Tryb developerski nie zbiera ani nie wysyła nowych statystyk.
  Błąd statystyk nie może blokować gry ani pozostałych tabel aplikacji.

Poprawki wskazane przez przegląd:

1. **Przenieść zapis kolejki poza UI i blokadę partii.** `Service#enqueue`
   wywołuje `Queue#push`, a ten synchroniczne `update_json`. Wywołują go
   wejście do programu/widgetu, odświeżanie GameScreen oraz runner pod
   `@sync.synchronize`. Sama wysyłka w tle nie usuwa tej zależności od
   dysku. W próbie kontrolowane 150 ms opóźnienia magazynu wydłużyło
   wywołanie `visit` do 151,8 ms na wątku wywołującym. To demonstracja
   ścieżki, nie pomiar rzeczywistego dysku użytkownika. Hook ma tylko
   przekazać mały, skopiowany wpis do ograniczonej kolejki; zarządzany
   worker utrwala i wysyła. Zachować izolację kont, deduplikację,
   obsługę niepewnego zapisu i przeładowania aplikacji.
2. **Rozstrzygnąć retencję obecności.** Obecne wygasanie filtruje odczyt,
   ale nie usuwa rekordów. Każdy kolejny stół tworzy nowy wpis każdego
   raportującego klienta; prawidłowe wyjście zeruje treść, a awaria
   pozostawia ostatnie wartości. Próba 20 kolejnych zamkniętych stołów
   pozostawiła 20 pustych rekordów, mimo braku aktywnych stołów. Ustalić
   i sprawdzić ograniczone sprzątanie/retencję przed długotrwałym wdrożeniem,
   z uwzględnieniem uprawnień serwera i ochrony aktywnych raportów. Nie
   używać ponownie publicznego ID rekordu dla różnych stołów, jeśli
   pozwoliłoby to łączyć ich aktywność. Historii wynikowych statystyk nie
   usuwać przy okazji sprzątania bieżącej obecności.
3. **Nie zgłaszać fałszywego konfliktu po odtworzeniu.** Gdy ta sama
   zapisana partia była już ukończona, a po restarcie programu zostanie
   ponownie odtworzona i ukończona innego dnia na tym samym profilu,
   trwała kolejka rzuca `ConflictingPayload` przy każdym kolejnym
   obserwowaniu wyniku. Pierwotny wynik pozostaje prawidłowo zachowany;
   to błąd raportowania/deduplikacji, nie udowodnione zatrzymanie gry.
   Traktować różnicę daty ponownego ukończenia jako „już zapisano”,
   zgodnie z istniejącą obsługą serwerową. Nadal odrzucać rzeczywiste
   konflikty tożsamości, gry lub trybu.
4. **Zgodność pomocy z fokusem.** Nowy opis Ctrl+W trafia też do historii
   głównego menu, chociaż sam skrót działa tylko na liście opcji. Test PR-a
   osobno potwierdza obie te sprzeczne rzeczy. Dopasować pomoc do zakresu
   klawisza razem z punktem 3 niniejszego planu, bez rozszerzania skrótu
   na pola tekstowe przy okazji.

Warunki wdrożenia: trzy nowe tabele `statistics_accounts`,
`statistics_events`, `room_presence` wymagają osobnej, zatwierdzonej
aktualizacji pełnego schematu, bez nadpisania starych tabel, ochrony,
zasobów lub quota. Zweryfikować filtry autorów/czasów i dostęp dwóch
zwykłych kont. Pseudonimowe identyfikatory nie są pełną anonimowością:
surowa tabela zawiera m.in. dzień/rodzaj gry oraz stałe statystyczne ID
konta. Użytkownik zatwierdził zakres zbierania dokładnie taki jak w PR #21,
w tym liczenie prywatnych stołów, i polecił samodzielnie utworzyć te trzy
tabele. Po świeżym odczycie MCP potwierdził konto deweloperskie „papierek”
i zgodę na ich dodanie. Nie zmieniać zakresu zbierania przy wdrażaniu
poprawek. Utworzenie tabel nie oznacza uruchomienia zbierania ani zgody
na włączenie całego PR-a do działającej aplikacji.

Status serwera: trzy tabele utworzone na koncie „papierek”, razem 11 tabel.
Podgląd serwera: osiem istniejących bez zmian, trzy nowe, bez resetu danych
i udostępnień. Odczyt kontrolny potwierdził schematy, uprawnienia, maski,
ochronę true, powiadomienia true i 16 MiB zasobów prywatnych. Serwer dopisał
do starych schematów tylko jawne puste domyślne filtry ([] / others);
pierwsza kontrola surowej równości to wykryła, kontrola semantyczna przeszła.
Nie zapisywano syntetycznych statystyk ani nie włączano kolekcji z PR-a.
Tymczasową deklarację w kliencie przywrócono, pomocnik usunięty z pamięci.
Dowody: diagnostics/pr21-22-review/server-{before,after}.json i pomocniki.

Przegląd lokalny: 23/23 celowane skrypty PR-a PASS, dodatkowe trzy próby
odtwarzają punkty 1–3 powyżej. „packaged_statistics_test” sprawdza binarne
wczytywanie źródeł, nie nową podpisaną paczkę. Bez żywych kont, zmian
serwera i pełnego runnera. Dowody poza repo: `diagnostics/pr21-22-review/`.
Zielone testy autora nie pokrywają wszystkich powyższych wymagań.

## 5. PR #22 — wspólna tarcza drużyny w deblu Axel Ponga

Przejrzany PR balteama/budyn1211:
https://github.com/papierek1997/elten-game-room/pull/22
Wersja: `15fe5d9bee16309d023dd0cde9117ec5cd59d633`, baza `0159ec3`.
Kandydat do włączenia; nie znaleziono w sprawdzonym zakresie błędu
wymagającego zmiany kodu autora.

- W Arcade tarcza zdobyta przez jednego partnera chroni obie osoby
  drużyny. Ponowne zdobycie ustawia obu pełne 10 sekund, nie dodaje czasu.
- Dźwięk włączenia/wygaśnięcia występuje raz dla drużyny, a obaj partnerzy
  słyszą go jako własny. Odbicie nadal należy do osoby, której przypada
  kolej; tarcza nie zmienia rotacji odbijających ani zasad singla.
- Zachować reguły i tłumaczenia autora. To świadoma zmiana zasady debla,
  nie przebudowa Communications. Do gry według tej zasady potrzebne są
  zgodne wersje uczestników. Przy wspólnym włączeniu PR-ów połączyć
  katalogi tłumaczeń bez utraty wpisów z żadnego PR-a.

8/8 celowanych skryptów PASS: wspólna tarcza, odnowienie, wygaśnięcie,
zmiany odbijającego, ludzie/boty, gospodarz-obserwator, audio, single
i lokalna symulacja dostawy relay. To próby lokalne, nie nowa żywa partia
ani odsłuch. Pierwsza komenda z nieistniejącą nazwą jednego testu zakończyła
się przed wykonaniem scenariuszy; poprawny przebieg ośmiu zapisano osobno.

## 6. Chińczyk — wyjście z bazy po wyrzuceniu 1

Nowa zaakceptowana reguła stołu: pole wyboru domyślnie zaznaczone dla
nowo tworzonych stołów. Wyrzucenie 1 również pozwala wyprowadzić pionek
z bazy na pole wejścia. Nie oznacza to wyjścia i dodatkowego ruchu o jedno
pole. Po tym ruchu kolejka przechodzi do następnego gracza — nie ma
ponownego rzutu za jedynkę.

- Dotychczasowe wyjście po 6 i opcja dodatkowego rzutu po 6 pozostają.
- Wyłączenie nowej opcji przy dotychczasowym ograniczeniu przywraca
  wyjście wyłącznie po 6. Jeżeli gospodarz dopuszcza wyjście po dowolnym
  wyniku, nadal obowiązuje ten szerszy wariant. Formularz i Ctrl+R nie
  mogą jednocześnie twierdzić, że jedynka pozwala wyjść, a jedynym
  dopuszczalnym wynikiem jest szóstka — dopasować etykiety/objaśnienia.
- Używać jednej walidacji legalnych ruchów dla gracza, bota i automatycznej
  obsługi jedynego ruchu. Nie wymuszać wyjścia z bazy, gdy gracz ma inny
  legalny ruch; jedynka daje dodatkową możliwość wyboru.
- Nie zmieniać położenia bezpiecznych pól, bicia, blokad, mety ani zasady
  trzech szóstek. Brak ruchu po jedynce kończy turę dotychczasową ścieżką.
- Nowa wartość domyślna nie może reinterpretować dawnych zdarzeń/pasów
  w już istniejących stołach i zapisach bez tego klucza. Zapewnić osobno
  domyślne opcje nowych stołów oraz odczyt historycznych opcji. Sprawdzić
  także zgodność z klientem, który jeszcze nie zna tej zasady.
- Uzupełnić zasady PL/EN i podsumowanie ustawień; testy obejmują 1/6/inny
  wynik, opcję włączoną/wyłączoną, wyjście po dowolnym wyniku, jeden/wiele
  legalnych ruchów, bota, następnego gracza i odtworzenie starych partii.

## 7. Trwałe lokalne preferencje prezentacji planszy

Zaakceptowane: zmiany sposobu prezentacji mają pozostawać po wyjściu ze
stołu i ponownym uruchomieniu ELTEN-a, a nie jedynie w bieżącym widoku.
Zapis lokalny w profilu, osobno dla każdej gry, nie na serwerze ani jako
zasada wspólnego stołu.

Potwierdzone obecne przełączniki:

- Szachy: obrót planszy, Ctrl+Shift+H.
- Warcaby: notacja numeryczna/szachowa, Ctrl+H, oraz obrót Ctrl+Shift+H.
- Planowany Chińczyk: nicki/kolory pod Ctrl+C, stosowane do wszystkich
  jego odczytów wskazanych w punkcie 2.

Szachy i warcaby mają dziś przełączniki oraz stan powierzchni, ale nie
trwały lokalny zapis tych wartości. Nie zakładać, że obecny stan kursora
lub jego zachowanie przy odświeżaniu jest takim zapisem. W pozostałych
sprawdzonych planszówkach nie znaleziono podobnego przełącznika, który
trzeba dopisać tylko na potrzeby tej funkcji.

- Wspólny, mały mechanizm preferencji, jawna lista dozwolonych pól
  deklarowana przez grę/powierzchnię. Nie zapisywać całego `surface_state`:
  pozycja kursora, wybrana figura, oczekujący ruch, szkic ustawienia liter
  albo tożsamość obserwowanej osoby nie są trwałą preferencją planszy.
- Przy zmianie zapamiętać wybór; odczyt przy otwieraniu następnego stołu
  nie może przesuwać fokusu ani odtwarzać starego zaznaczonego ruchu.
  Nie wykonywać odczytów/zapisów dysku na każdym odświeżeniu lub strzałce.
  Błąd zapisu preferencji nie przerywa partii ani nie zmienia jej stanu.
- Obrót musi uwzględniać zmianę miejsca/koloru i rolę obserwatora.
  Propozycja do wdrożenia: dla gracza pamiętać własną/przeciwną stronę
  na dole, względem naturalnego widoku aktualnego miejsca, zamiast
  przypadkowego indeksu osoby z poprzedniego stołu. Dla obserwatora
  zachować wybór strony, bez zapamiętywania dawnych nicków.
- Brak, niepoprawna lub nieobsługiwana wartość przywraca właściwy
  domyślny widok danej gry. Aktualizacja nie kasuje innych preferencji.
- Sprawdzić nowe stoły, rewanż, restart, zmianę gracza/obserwatora,
  zmianę rozmiaru warcabnicy, niezależność gier i profili oraz to, że
  reguły, zdarzenia serwerowe i widok innych osób pozostają niezmienione.

## 8. Dodatkowe polskie imiona botów

Dodać do obecnej polskiej puli, nie zastępując dotychczasowych nazw.
Zachować dokładnie pisownię, wielkość liter i znaki podane przez użytkownika
(również „Andżej”, „amelinium” i „Gienek Gienerator”). Lista 22 nowych nazw:

- Klara Sobieraj
- asystent Google
- Max z Orange
- Siri
- Lolek
- Marek Dyrektor
- Baltazar Świździpała
- ciocia Henia
- Wujo Janek
- Wiesław
- Jaskier
- Aluś
- Eulalia
- Andżej
- Audiobukis
- Natala
- Gienek Gienerator
- Siostra Konsoleta
- amelinium
- Mymłon
- Generał Italia
- Pułkowniciowy

Nie zmieniać puli angielskiej ani nazw już obecnych botów. Korzystać
z istniejącego losowania nazw i zapobiegania kolizjom przy stole.
Przy wdrożeniu sprawdzić pełną pulę, polskie znaki i komunikaty/historię
z wylosowanym imieniem, bez dodawania słowa „komputer”.

## 9. Pytania zgłoszone na forum — „odyn nie był gejem”

Przy wdrożeniu wejść przez MCP do grupy ELTEN Game Room, na forum
„Błędy”, i odnaleźć wątek wskazany przez użytkownika jako „odyn nie był
gejem”. Przeczytać i pobrać materiał z całego wątku, nie tylko pierwszego
postu; uwzględnić sprostowania i ustalenia z kolejnych odpowiedzi.

- Odnaleźć każde zgłoszone pytanie w aktualnych zestawach, z jego ID,
  odpowiedziami, oznaczoną poprawną odpowiedzią i kontekstem pytania.
- Sprawdzić zgłoszenia na podstawie wiarygodnych źródeł i rzeczywistego
  brzmienia pytania. Tytuł ani opinia w poście nie są samodzielnym dowodem
  błędu; rozróżniać mitologię, książki, gry i ekranizacje, jeśli ma to znaczenie.
- Poprawić potwierdzone błędy treści, klucza odpowiedzi, języka lub
  przypisania zestawu, zachowując ID. Nie powtarzać pełnego audytu wszystkich
  baz przy tej pracy ani nie usuwać innych pytań na podstawie podobieństwa.
- Zapisać decyzję, źródła i powód dla każdego zgłoszenia, także gdy pytanie
  było już poprawione lub zarzut się nie potwierdził. Przy braku możliwości
  potwierdzenia po rzetelnym szukaniu stosować uzgodnioną politykę audytu,
  nie oznaczać pytania jako zweryfikowanego bez dowodu.
- Po zmianie danych zaktualizować wymagane wersje/sumy kontrolne i wykonać
  celowaną walidację zestawów oraz wczytywania zmienionych pytań.

Na tym etapie zapisano wyłącznie zadanie. Nie czytano jeszcze tego wątku
ani nie zmieniano pytań; dostęp do forum może oznaczyć posty jako przeczytane.
Nie publikować odpowiedzi na forum bez osobnego polecenia.

Na obecnym etapie dopisano plan i przeprowadzono powyższy przegląd PR-ów.
Kod roboczej gałęzi produkcyjnej i paczka pozostają bez zmian; osobno
zatwierdzona operacja serwerowa jest opisana w punkcie 4.
