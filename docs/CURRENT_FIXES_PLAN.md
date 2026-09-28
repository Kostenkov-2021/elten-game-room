# Bieżący plan poprawek

Stan: 27 września 2026. Wdrożenie wszystkich siedmiu punktów zostało
zatwierdzone i rozpoczęte. Historyczne opisy „bez implementacji” poniżej
opisują etap uzgadniania, nie ograniczają obecnego polecenia. Postęp i wyniki
prób: [raport wdrożenia](CURRENT_FIXES_IMPLEMENTATION.md).
Do dotychczasowych punktów 1–2 dopisano konkretny
zakres zmian dla wolnej sieci w punkcie 3 oraz poprawkę ustawienia planszy
i numeracji warcabów w punkcie 4. Punkt 5 dotyczy przycięcia standardowego
dźwięku górnej piłki w Audio Ballu, punkt 6 — natywnego menu użytkownika
z listy osób przy stole, a punkt 7 — odczytu obsady wybranego stołu pod
Ctrl+W. Polecenie „wdrażamy plan” odnosi się do tego
dokumentu, nie do ponownego opracowywania tych rozwiązań.
Ten zakres jest oddzielny od zakończonych punktów 1–9 w
[poprzednim planie](POST_239_FIXES_PLAN.md).

## Wspólny warunek wdrożenia i sprawdzenia wszystkich zmian

- Każda zmiana z tego planu, także dopisana później, wymaga zarówno
  celowanych testów lokalnych, jak i prób w rzeczywiście działającym
  ELTEN-ie na żywych kontach. Sama symulacja lub poprawny wynik testu
  lokalnego nie zamyka punktu planu.
- Liczbę kont dobrać do sprawdzanego zachowania: jedno dla samodzielnej
  obsługi interfejsu, ustawień lub odtwarzania dźwięku; dwa dla rozgrywki
  i dostarczania zmian drugiej osobie; trzy dla obserwatora, zastępstw
  i przekazywania gospodarza; cztery dla pełnego debla lub innych
  scenariuszy wymagających czterech niezależnych uczestników. Używać
  rzeczywistych osobnych kont, nie zastępować wymaganych klientów botami.
- Przed próbami wczytać właściwe źródła do wszystkich używanych kopii
  i potwierdzić, że testowana jest zmiana, a nie wcześniejsza wersja.
  Sprawdzać normalną ścieżkę interfejsu i efekt u pozostałych uczestników,
  nie tylko bezpośrednie wywołanie metody lub stan gospodarza.
- Oprócz nowego zachowania sprawdzić dotknięte istniejące funkcje i istotne
  przypadki graniczne. Szczegółowe wymagania poszczególnych punktów oraz
  odpowiednie scenariusze z sekcji 3.10 nadal obowiązują. Nie powtarzać
  pełnego lokalnego zestawu zamiast celowanych prób zmienionych miejsc.
- Zapisać wynik osobno dla testów lokalnych i żywych, z liczbą kont,
  sprawdzonymi scenariuszami oraz ograniczeniami, np. jeden komputer/łącze
  albo brak fizycznego odsłuchu. Nie przedstawiać nieukończonej próby jako
  sukcesu; przy braku możliwości testu wskazać, co pozostało do sprawdzenia.
- Próby wykonywać na własnych stołach testowych i po zakończeniu usunąć
  wyłącznie dane tych prób. Nie naruszać cudzych ani bieżących partii
  użytkownika. Użytkownik zatwierdził rozpoczęcie wdrożenia oraz aktualizację
  kopii ELTEN-a, jeżeli nie spełniają wymaganego API 3.0.4.

## 1. Ukrywanie rozgrywanych stołów po 45 minutach bez aktywności

Stan: 27 września 2026 — zapisany szkic, bez implementacji. Użytkownik
polecił zapisać omówiony projekt, nie wdrażać go ani budować paczki.

### Zachowanie

- W oknie „Dołącz” i w widgecie ukrywać stoły ze statusem `playing`,
  na których przez co najmniej 45 minut nie było rzeczywistej aktywności.
- Stołów oczekujących na rozpoczęcie nie obejmować tym filtrem.
- To wyłącznie filtr listy, nie zamknięcie sesji, usunięcie stołu,
  przerwanie partii ani stwierdzenie, że stół jest uszkodzony.
- Kolejny ruch lub wiadomość czatu przywraca widoczność po opublikowaniu
  aktywności i zwykłym odświeżeniu listy. Nie dodawać nowego ekranu ani
  dodatkowego kroku dołączania.
- Nie zmieniać wejścia z zaproszenia, obsługi powiadomień, wykrywania
  własnego stołu, otwartej partii ani uprawnień do dołączenia.
- Starszy stół bez wiarygodnego znacznika pozostaje widoczny. Nie zastępować
  brakującej informacji datą utworzenia, zerem lub czasem pierwszego odczytu.

### Znacznik aktywności i obciążenie

Dodać osobne `last_activity_at` do publicznego opisu discovery. Obecne
`updated_at` pozostawić bez zmiany znaczenia: dla odkrytego stołu jest dziś
inicjalizowane czasem utworzenia i nie nadaje się do tego filtra.

Liczyć zatwierdzone rozpoczęcie partii, ruchy/zdarzenia rozgrywki i wiadomości
czatu. Znacznik pochodzi z serwerowego czasu zdarzenia, nie z chwili jego
odebrania lub odtworzenia historii. Pingi, utrzymanie połączenia, powtarzane
komunikaty synchronizacji, przeglądanie listy i samo wejście obserwatora nie
zerują bezczynności. Rzeczywiste ruchy botów są aktywnością.

Każde nowe zdarzenie aktualizuje tylko wartość w pamięci. Gospodarz publikuje
najnowszą wartość w tle najwyżej raz na minutę i tylko po zmianie aktywności:
100 ruchów w minutę nie oznacza 100 dodatkowych żądań. Oczekujące ostatnie
zdarzenie musi zostać opublikowane także wtedy, gdy nie nastąpi następny ruch;
po opróżnieniu tej zaległości bezczynny stół nie generuje aktualizacji.
Nie wysyłać nowej daty tylko dlatego, że nadszedł termin publikacji.

Wysyłka nie może blokować akcji, klatek realtime ani interfejsu. Nie dodawać
osobnego odpytywania każdego stołu przez przeglądającego. Ograniczenie
częstotliwości dotyczy znacznika, nie dotychczasowych aktualizacji statusu,
obsady i gospodarza. Niepowodzenie publikacji nie unieważnia wykonanego ruchu.
Uwzględnić opóźnienie publikacji i odświeżenia listy przy granicy 45 minut;
nie obiecywać widoczności zmieniającej się natychmiast co do sekundy.

### Miejsca planowanych zmian

1. `lib/live_session_store.rb`: wyliczanie znacznika z zaakceptowanych
   rekordów w `project_room_records`, publikacja przez `publish_discovery`
   i odczyt w `table_from_metadata`/`table_from_discovered`. Zachować
   informację przy zmianie gospodarza i porządkowaniu historii; weryfikować
   tożsamość sesji przed wykonaniem opóźnionej publikacji.
2. `lib/lobby_repository.rb`: jeden wspólny warunek bezczynności i opcjonalne
   filtrowanie w `open_table_snapshots`, domyślnie niewłączone. Warunek:
   `playing`, wiarygodny znacznik i upływ 45 minut według zsynchronizowanego
   zegara serwerowego. Nie filtrować bezwarunkowo w `discover_rooms`, bo
   surowe wyszukiwanie jest potrzebne również innym ścieżkom aplikacji.
3. `__app.rb`: włączyć filtr tylko w `show_join_table`,
   `show_tables_for_game` (lista stołów wybranej gry) oraz
   `load_widget_table_snapshots`. Pozostałe wywołania pozostawić bez filtra.
4. `lib/axel_pong/peer_play.rb` i `lib/audio_ball/client.rb`: zgłaszać
   rzeczywiście zaakceptowane serwy/odbicia, lokalne i odebrane, również
   botów. Nie opierać się wyłącznie na punktach zapisanych w LiveSessions,
   aby długa wymiana bez bramki nie wyglądała na bezczynność. Wspólne
   przekazanie informacji przez transport zapisuje ją w pamięci, bez HTTP
   w klatce i bez zmiany fizyki, routingu, potwierdzeń lub reguł obrony.

### Weryfikacja przy późniejszym wdrażaniu

- Granica 45 minut, opóźniona publikacja ostatniego ruchu i ponowne pojawienie
  się po aktywności; brak odmłodzenia przy ponownym odczycie historii.
- Stoły oczekujące, stary/brakujący znacznik, przestawiony zegar komputera,
  powrót do istniejącej partii oraz wejścia z zaproszenia i powiadomienia.
- Ruchy i czat za innym oknem; Pong/Audio Ball, ludzie/boty, gospodarz będący
  obserwatorem oraz sama synchronizacja bez gry.
- Zmiana gospodarza, nowa partia i spóźnione zadanie starej sesji; zachowanie
  dotychczasowej obsługi błędów i aktualizacji statusu/obsady.
- Limit liczby publikacji, brak pracy sieciowej w UI i zmieszczenie opisu
  wraz z opcjami i danymi kontroli w limicie discovery 1024 bajtów.

Bez nowych tabel serwerowych, zmian w ELTEN-ie i ingerencji w przebieg gier.
Przy zapisywaniu tego szkicu nie wykonano implementacji, testów, hotloadu,
zmian serwerowych, pakowania, podpisywania ani publikacji na GitHubie.

## 2. Chińczyk — spójne nicki/kolory i krótsze komunikaty

Stan: 27 września 2026 — przegląd źródeł i propozycja do uzgodnienia,
bez implementacji. Użytkownik zgłosił niepełne stosowanie filtra kolorów,
słowo „gracz” przed kolorem, nadal odczytywane numery pionków przy ruchach
i niespójną prezentację historii. Ten punkt doprecyzowuje prezentację
historii z punktu 2 dokumentu `POST_239_FIXES_PLAN.md`: nie zmieniać jej źródłowych danych, ale lokalny odczyt
zdarzeń gry ma respektować aktualny przełącznik.

### Potwierdzone w obecnym kodzie

- `games/ludo.rb`, `display_player`: nick/kolor jest stosowany w opisach
  pozycji, wyborze ruchu i skrótach 1–4, V/Shift+V, P/Shift+P, D, S i T.
  Nie jest to wspólna ścieżka dla wszystkich komunikatów gry.
- `apply_roll!` oraz `apply_pawn_move_index!` tworzą historię z
  `participant_name`. Ruch i zbicie nadal mają tekst z „pionek” i numerem.
  `describe_event` odczytuje te same gotowe wpisy, więc problem obejmuje
  zarówno mowę na bieżąco, jak i historię.
- Automatyczne ogłoszenia tury, wynik oraz początek partii korzystają
  z metod `Base`, które podają nick. Dlatego T może podawać kolor, a
  automatyczny komunikat tury i zakończenia — nazwę użytkownika.
- Chińczyk nie nadpisuje `history_entries_for_display` ani
  `describe_event_for_display`. Istniejące punkty rozszerzenia pozwalają
  zmienić lokalną prezentację bez przepisywania zapisanych zdarzeń.
- `locale/PL.po`: „Kolej gracza %{player}”, „Oczekiwanie na gracza
  %{player}” i „Odczytaj pionki gracza %{player}” są także formatowane
  kolorem, dając konstrukcje w rodzaju „gracza czerwony”. Część kluczy
  współdzielą inne gry; nie zmieniać ich globalnie przy tej poprawce.
- `test/ludo_post239_test.rb` sprawdza skróty, pozycje i niezmienność
  źródłowej historii, lecz nie sprawdza jej przefiltrowanej prezentacji,
  automatycznej mowy ruchów ani polskich zdań po podstawieniu koloru.

### Proponowane zachowanie

1. Jeden lokalny sposób formatowania uczestnika dla wszystkich odczytów
   rozgrywki: pozycji, wyboru ruchu, rzutu, ruchu, zbicia, braku ruchu,
   utraty kolejki po trzech szóstkach, tury, początku i wyniku partii.
   Ten sam wybór obowiązuje w historii oraz jej nawigacji klawiszami.
2. Nie doklejać słowa „gracz” do nazwy koloru. Używać neutralnych zdań
   Chińczyka, np. „Ruch: czerwony”, „Oczekiwanie na ruch: niebieski”,
   „czerwony, brak możliwego ruchu”, „czerwony wygrywa grę”. Ten sam
   układ zdań może przyjmować nick, bez prób odmieniania nazwy konta.
3. Usunąć słowo „pionek” i numer identyfikujący pionek z indywidualnych
   opisów ruchu i zbicia, nie tylko z list pozycji. Przykładowy ruch:
   „papierek, z toru 5 na tor 9” albo „czerwony, z toru 5 na tor 9”.
   Przy wyjściu z bazy i wejściu do domu/mety poprawnie odmieniać nazwy
   miejsc zamiast mechanicznego „z tor 5”. Przy zbiciu nadal wskazać
   wykonawcę, właściciela zbitego pionka, pole i powrót do bazy;
   nie zgubić liczby zbitych pionków, gdy jest ich kilka.
4. Numery pól, wartości kości oraz liczebność w bazie/na mecie pozostają.
   Zachować osobne pozycje współdzielące pole i stabilne ID pionków pod
   Enterem. Filtr nie może wybierać innego pionka ani scalać legalnych ruchów.
5. Po Ctrl+C przerysować istniejącą historię według nowej prezentacji,
   bez odczytania jej od początku, ponowienia starych zdarzeń/dźwięków,
   utraty kategorii, pozycji historii, szkicu czatu lub zaznaczonego ruchu.
   Zapamiętany lokalny wybór ma obowiązywać od pierwszej prezentacji
   po wejściu do stołu, także przy komunikatach za innym oknem ELTEN-a.
6. C nadal celowo podaje jednocześnie nick i przypisany kolor. Nie
   zastępować nicków kolorami w czacie, liście uczestników i zdarzeniach
   organizacyjnych stołu (dołączenie, zaproszenie, gospodarz, zastępstwo).
   Pomoc skrótów gry również nie może tworzyć etykiet „gracza czerwony”.

### Sposób wdrożenia i granice

- Główne zmiany w `games/ludo.rb`: wspólne formatowanie opisów oraz
  nadpisanie istniejących metod prezentacji historii, mowy, tury i wyniku.
  Wzorem jest lokalna prezentacja notacji w Warcabach, nie zamiana nicków
  przez wyszukiwanie i podmienianie fragmentów już złożonego tekstu.
- Zachować źródłowe wpisy historii i ich klucze; tworzyć kopie do wyświetlenia.
  Potrzebne dane opisowe (miejsce uczestnika, początek/koniec ruchu, zbicie)
  przechowywać w lokalnej reprezentacji historii. Nie zmieniać zdarzeń
  serwerowych ani formatu zapisanej partii wyłącznie dla sposobu odczytu.
- Kolor odpowiada stałemu miejscu. Dawny wpis po zastąpieniu człowieka
  botem musi zachować dawnego autora w trybie nicków i właściwy dla chwili
  zdarzenia kolor w trybie kolorów. Nie szukać historycznych autorów tylko
  na aktualnej liście uczestników; nie naruszać `GameRoomParticipantReplay`.
- W `lib/game_screen.rb` sprawdzić kolejność inicjalizacji preferencji:
  obecnie `combined_history_items` wywoływane jest przed przypisaniem
  `board_presentation_preferences` i odtworzeniem stanu powierzchni.
  Ograniczyć ewentualną zmianę do poprawnej kolejności prezentacji, bez
  ruszania wykonawcy gry, synchronizacji i obsługi klawiszy.
- Dodać odpowiednie teksty PL/EN w istniejącym systemie lokalizacji,
  doprecyzować `docs/rulebooks/ludo.json` i wygenerowane zasady oraz pomoc.
  Nie zmieniać przy okazji wspólnych komunikatów innych gier.

### Celowana weryfikacja przy wdrażaniu

Sprawdzić obie prezentacje w PL/EN: rzut, ręczny i automatyczny ruch,
wyjście z bazy, tor domowy, meta, zbicie, brak ruchu, trzy szóstki, kolejna
tura i zakończenie. Porównać mowę, historię, nawigację historii oraz skróty
1–4, V/Shift+V, P/Shift+P, D, S, T i C. Uwzględnić obserwatora, zastępstwo,
zmianę gospodarza, zapis/odtworzenie, zapamiętany filtr po nowym wejściu,
Ctrl+C bez nowego zdarzenia i komunikaty za innym oknem.

Zachować test niezmienności źródłowej historii; dodać osobno sprawdzenie
tekstu wyświetlanej kopii. Przy dotknięciu wspólnego `GameScreen` sprawdzić
także istniejącą prezentację Warcabów i zachowanie fokusu/szkicu czatu.
Na tym etapie zmieniono wyłącznie plan; nie uruchamiano testów ani nie
wczytywano zmiany do ELTEN-a i nie przebudowywano paczki.

## 3. Wolne połączenie nie blokuje lokalnej obsługi Game Roomu

Stan: 27 września 2026 — projekt gotowy do implementacji na polecenie
użytkownika. Poniższe decyzje wynikają z przeglądu kodu, wcześniejszych
pomiarów na żywym ELTEN-ie oraz nowych lokalnych prób porównawczych.
Nie jest to polecenie wdrożenia teraz. Nie zmieniać przy okazji punktów 1–2,
zasad, siły botów, protokołu Communications ani źródła prawdy o partii.

### 3.1. Efekt dla użytkownika i granice zmiany

- Podczas oczekiwania na ruch, czat lub odświeżenie nadal działają Tab,
  strzałki, przeglądanie aktualnej ręki/planszy, historia, odczyty informacji,
  pomoc, głośność i pisanie w czacie. Dotyczy to wspólnych powierzchni kart,
  pionków, kości, kostek domina, plansz i odpowiedzi, nie tylko UNO.
- Po wysłaniu jednej akcji nie wysyłać następnej z tego samego ekranu,
  dopóki nie jest znany wynik poprzedniej. Powtórzony Enter/Spacja nie
  tworzy kolejki ruchów do późniejszego odegrania. Karta nie znika na niby,
  pionek nie wykonuje zatwierdzonego ruchu na podstawie samego wyboru.
- Niepowiązane żądanie HTTP nie odbiera sterowania Pongiem/Audio Ballem,
  gdy bieżąca wymiana jest nadal poprawnie zsynchronizowana. Zapis bramki
  nie odcina poruszania własną paletką, lecz nadal blokuje następny serw.
- Lobby i lokalne kategorie ustawień nie czekają na dodatkowy odczyt
  historii lub subskrypcji. Dane wymagające serwera mają jawny stan
  ładowania/niepowodzenia, a nie pozornie pustą listę.
- Nie obiecujemy szybszej dostawy sieciowej: zatwierdzenie ruchu, zapis,
  dołączenie, wynik bramki i reakcja odległego przeciwnika nadal mogą
  wymagać oczekiwania. Usuwamy niepotrzebne związanie z nim lokalnego UI.

### 3.2. Na czym opieramy zakres

Wcześniejsza próba `diagnostics/slow-network-239` opóźniała dostarczenie
odpowiedzi HTTP o 1/3 s, bez spowalniania całego systemu. Zapis czatu
i dobranie w UNO przy opóźnieniu 3 s trwały około 3,16 s, z zerem aktualizacji
formularza w tym czasie. Otwarcie ustawień czekało około 3,06 s przed
utworzeniem formularza. Automatyczne pobranie historii lobby odtworzyło
ten sam problem. Samo sprawdzanie najnowszego ID z `ui: form` aktualizowało
formularz około 59–60 razy w podobnym czasie.

Nowe próby projektowe są poza produkcją: `diagnostics/slow-network-plan-239`.

- Pong, wirtualne 6,4 s oczekiwania na już uzgodniony punkt: po odpięciu
  widoku pozycja własnej paletki pozostała 15; przy zachowaniu formularza
  i jego istniejącego timera zmieniła się z 15 na 29. W drugim przypadku
  wykonano 400 aktualizacji formularza. W obu przypadkach wynik zmienił się
  dopiero po potwierdzeniu, dokładnie o jeden punkt; nie wymuszono reconnectu.
- Audio Ball, istniejący lot i 2,24 s niepowiązanego oczekiwania HTTP:
  to samo polecenie obrony zostało pominięte bez widoku i przyjęte przy
  zachowaniu widoku. Próba używa obecnych klientów/silników, ale atrap
  formularza, transportu i wejścia; nie jest testem fizycznej klawiatury.
- `GameRoomServerTables`: zatrzymanie żądania w kontrolowanej barierze
  blokuje dziś także lokalne `fetch` i `reset_access!`. Oddzielny prototyp
  z dwiema blokadami pozwolił obu metodom zakończyć się przed odpowiedzią
  sieci. Spóźniona odmowa starej generacji nie nadpisała nowego stanu dostępu.

Nie utożsamiać tych wyników z odtworzeniem konkretnego zgłoszenia z meczu
użytkownika ani z pomiarem opóźnień Communications/P2P. Nie testowano teraz
wszystkich rodzajów plansz na żywo. Wyniki uzasadniają poniższy projekt;
testy gotowej implementacji pozostają warunkiem jej przyjęcia.

### 3.3. Wspólny tryb oczekiwania zamiast osobnych poprawek gier

Pozostawić `EltenAPI::Tasks.run` jako wykonawcę istniejących operacji
użytkownika. Nie dodawać drugiego wykonawcy ruchów, pętli botów ani UI
w wątku roboczym. Dodać mały, ograniczony do jednego formularza kontekst
oczekiwania, np. `GameRoomUI::PendingOperation` w nowym
`lib/game_room_pending_operation.rb`. Nazwa jest projektowana, nie istnieje
jeszcze w kodzie.

Kontekst ma przechowywać właściciela formularza, identyfikację stołu/partii
i generację widoku, token obecnego zadania oraz tryb obsługi wejścia.
Nie posiada własnego wątku, kolejki żądań ani timera fizyki. Jego `update`
obsługuje nadal ten sam formularz, a `ensure` zdejmuje tylko własne blokady.
Nie wybierać formularza przez zgadywanie ostatniego elementu `$activecontrols`.
Należy przekazać jawnie widok należący do tej operacji.

Polityka podczas oczekiwania:

| Działanie | Ustalone zachowanie |
| --- | --- |
| Tab, strzałki, historia, zaznaczanie/kopiowanie tekstu | Działają na ostatnim potwierdzonym widoku. |
| Edycja czatu | Działa; tekst i pozycję odczytujemy ponownie przed odświeżeniem. |
| Odczyt wyniku, tury, ręki, planszy; lokalna pomoc i głośność | Działają bez nowego żądania sieciowego. |
| Lokalne sortowanie i prezentacja planszy | Działają z zachowaniem tożsamości zaznaczonego elementu. |
| Z/Shift+Z | Mogą przenieść kursor, ale nie zagrywają automatycznie podczas oczekiwania. |
| Enter/Spacja/skrót wysyłający kolejną akcję, drugi czat | Nie wysyła i nie kolejkuje. Krótki komunikat o oczekiwaniu, bez zalewania mową przy trzymanym klawiszu. |
| Wybór karty otwierający kolor/paczkę, edycja układu, formularz oferty | Nie rozpoczyna kolejnego etapu operacji do zakończenia bieżącej. Nawigacja pozostaje dostępna. |
| Restart, zapis partii, zmiana obsady/gospodarza, opuszczenie stołu, Ctrl+J | Nie wykonuje zagnieżdżonej operacji na stole. Po zakończeniu można wywołać ponownie; nie odgrywać tych poleceń automatycznie. |
| Wejście z widgetu/powiadomienia podczas zadania | Pozostaje w istniejącym mechanizmie pojedynczej instancji i jego bezpiecznych granicach; nie konsumować wejścia w środku zapisu. |
| Escape | W lokalnej pomocy zamyka pomoc. W oczekującej operacji korzysta z jej istniejącego anulowania i odczytu rozstrzygającego; nie oznacza sam w sobie cofnięcia zapisu lub wyjścia ze stołu. |

Nie otwierać po 5 s nowego modalnego okna, które przejmie fokus aktywnej
planszy. Dla tego trybu po istniejącym progu 5 s podać raz status oczekiwania;
anulowanie korzysta z tego samego tokenu i obsługi błędów co obecnie.
Dla operacji bez istniejącego widoku zachować dotychczasowe okno zadania.
Nie anulować zapisu przez zabicie własnego dodatkowego wątku.

### 3.4. Konkretne zmiany wspólnego kodu partii i poczekalni

1. `lib/game_screen.rb`, `wait_for_action`, `run`, `network_task`,
   `refresh_input_ui`, `submit_action`, `submit_runner_action`,
   `submit_inline_action` i obsługa automatów:
   - Nie wykonywać `detach_view` oraz `layout.begin_bindings` tylko dlatego,
     że `wait_for_action` oddaje sterowanie do odczytu/zapisu tej samej partii.
     Zachować widok na czas tej operacji; sprzątanie wykonać przy rzeczywistym
     opuszczeniu/zastąpieniu widoku lub błędzie kończącym ekran.
   - Zastąpić ścieżkę `refresh_input_ui` zwracającą wyłącznie czat/`:none`
     jawnym kontekstem oczekiwania dla całego należącego do operacji widoku.
     Nie stosować globalnego „każde `network_task` dostaje dowolny `form`”.
   - Rozdzielić lokalne odczyty/nawigację od handlerów ustawiających kolejną
     akcję. Pozostawione stare timery nie mogą rekurencyjnie uruchomić
     `network_task` ani czekać na blokadę zajętą przez bieżący worker.
     Sygnały synchronizacji czekają na dotychczasowe bezpieczne przetworzenie;
     nie konsumować ich bez możliwości zastosowania wyniku.
   - Po zakończeniu pobrać **najnowszy** snapshot fokusu, kursora, historii,
     wyboru ręki i szkicu, dopiero potem zastosować wynik i przewiązać ekran.
     Nie przywracać pozycji uchwyconej przed kilkusekundowym oczekiwaniem.
     - Zachować `StaleView`, rewizję zdarzeń, epokę obsady, właściciela,
     zamrożenie sesji i weryfikację faktycznego przyjęcia ruchu. W Monopoly
     zachować aktualny replay po `trade_prepare`; żadnego ominięcia walidacji.
   - Istniejący asynchroniczny runner botów nie oznacza „zajętego całego UI”.
     Nie blokować legalnych reakcji na cudzą turę tylko dlatego, że bot myśli.
     Nie zmieniać `bot_task` ani zasad przechwytywania/wołania UNO i Makao.
     Blokada dotyczy drugiej transakcji danego interfejsu, nie samej tury bota.
2. `lib/game_room_ui.rb`, `Form#update`, `game_room_hotkeys_active?`,
   `accept_game_room_invitation` i granica `dispatch_game_room_entry`:
   - Kontekst oczekiwania jawnie utrzymuje lokalne skróty tego formularza,
     mimo że zakończyło się jego `wait`. Uwzględnia rzeczywisty fokus/okno;
     nie steruje zasłoniętą grą klawiszami z Wiadomości lub innego dialogu.
   - Przed Ctrl+J, menu kontekstowym i wejściem zewnętrznym sprawdza bezpieczną
     granicę oczekującej operacji. Pomoc pozostaje odczytem, nie drugim ekranem
     gry. Odtwarza wcześniejsze flagi po zakończeniu także przy wyjątku.
3. `lib/game_layout.rb`, `Screen` i `Bindings`:
   - Związać kontekst z konkretną generacją układu. Lokalna aktualizacja nie
     dodaje kolejnych handlerów/timerów. Reconcile nadal zachowuje obiekty
     kontrolek, kategorię historii i stabilne ID kart/pól.
   - Snapshot po oczekiwaniu obejmuje zmiany wykonane podczas zadania.
     Zmiana sesji/unload zamyka kontekst, a późny wynik nie dotyka nowego UI.
4. `lib/game_surfaces.rb`, `ActionEmitter` i wspólne powierzchnie:
   - Dodać wspólną bramkę aktywacji oraz pomocnik rejestracji selekcji/przycisku,
     sprawdzający ją **przed** lokalną zmianą etapu i otwarciem podwyboru.
     Samo odrzucenie `emit_action` na końcu jest za późne dla koloru/paczki.
     `emit_action` zachowuje dodatkową kontrolę jako ostatnią granicę.
   - Podłączyć aktywacje `GridBoard`, `CardTable`, `FleetGrid` oraz plików
     `game_surfaces/{packet_cards,pawn_track,piece_board,dice_tray,
     roll_and_score,word_board,answer_sheet,question_surface,review_surface,
     command_panel,taboo_surface}.rb`. `TileHandSurface` i `MeldHandSurface`
     dziedziczą bramkę kart; ich dodatkowe ścieżki również jej przestrzegają.
     `CompositeSurface` przekazuje stan dzieciom — blokada samego rodzica
     nie wystarczy. To zmiany prymitywów interfejsu, nie obejścia w każdej grze.
   - Dla `handle_command` dodać jawne dopuszczenie odczytu/prezentacji na
     powierzchni; domyślnie polecenie nieznane nie jest dozwolone w oczekiwaniu.
     Przykłady dopuszczone: `sort_cards`, `announce_packet`, `word_rack`,
     `word_read`, `word_preview`; nawigacja grywalnych kart z wyłączonym
     automatycznym zagrywaniem. Typ `:surface` sam w sobie nie oznacza odczytu.
     `:announcement` i istniejące odczytowe `:browse` można obsługiwać dalej;
     `:action`, `:choice`, `:form`, `:staged_form` i `:number_input` zaczekają.
   - Odczytowe listy `browse_shortcut_choices` oraz F1/Ctrl+F1 podczas
     oczekiwania otwierać przez istniejącą obsługę pomocy w tle należącą do
     formularza. Nie uruchamiać wewnątrz `TaskUI#update` zagnieżdżonego
     blokującego `Form#wait`, który znowu odciąłby timer gry. Zamknięcie
     takiej listy wraca do nadal oczekującego formularza, bez drugiego zadania.
5. `__app.rb`, `show_table_screen`, `load_room_state`, `run_network_task`:
   - Zastosować ten sam jawny kontekst do oczekiwania poczekalni: odczyt
     członkostwa, czat i zatwierdzanie operacji. Nie czyścić wiązań przed
     operacją, jeśli formularz ma nadal obsługiwać lokalne wejście.
   - Nie przekazywać starego formularza do zadania tworzącego lub otwierającego
     inne okno. Stół, partia i formularz muszą należeć do tego samego kontekstu.
   - Zachować istniejącego wykonawcę/presentera tła. Zmiana nie dodaje drugiego
     nasłuchiwania, heartbeatów ani ponownego ogłaszania tych samych zdarzeń.

Nowe krótkie statusy ładowania/oczekiwania dodać do aktualnego systemu
lokalizacji (źródłowy angielski i polski katalog), bez zmiany istniejących
tłumaczeń. Napisy kontrolek mają przechodzić dotychczasową normalizację UTF-8.
Nie dodawać użytkownikowi nowej opcji włączającej tę poprawkę.

### 3.5. Czat: uchwycony tekst i bezpieczne potwierdzenie

Zmiany: `GameScreen#submit_chat`, `clear_chat_draft`, czat poczekalni
w `__app.rb#show_table_screen` oraz `GameSurfaces::RefreshAwareEditBox`
w `lib/game_surfaces.rb`.

- Przy Enterze na wątku UI pobrać niezmienną kopię tekstu, generację szkicu
  i tożsamość kontrolki/stołu. Worker nie odczytuje później `layout.chat.text`.
- W kontrolce prowadzić lokalną generację zmian treści, wykorzystując natywne
  `:change` i nasze programowe czyszczenie. Sama równość tekstów nie wystarcza:
  skasowanie i ponowne wpisanie identycznej wiadomości też jest nową edycją.
- Do odpowiedzi pozostawić wysyłany tekst w polu. Użytkownik może go edytować;
  czyszczenie po sukcesie jest dozwolone tylko dla nadal tej samej generacji
  szkicu i kontrolki. Zawsze zachować pozycję/zaznaczenie nowszego tekstu.
- Błąd nie czyści pola. Nie wprowadzać automatycznej powtórki wiadomości
  o niepewnym wyniku. Sukces dodaje historię/dźwięk raz, zgodnie z istniejącym ID.
- Polecenie ruchu wpisane w czacie korzysta z tego samego warunku zamiast
  bezwarunkowego `clear_chat_after_action`. Nie dopisywać wyłącznie poprawki
  do zwykłych wiadomości, zostawiając utratę szkicu po poleceniu.

### 3.6. Lobby, ustawienia i dostęp do tabel

**Lobby — `__app.rb#show_main_menu`, `load_lobby_history`,
`poll_lobby_activity`; `lib/game_room_screens.rb#MainMenu#wait`.**

- Utworzyć menu z już posiadaną lokalną historią, bez pobierania jej przed
  konstrukcją formularza. Pierwszy odczyt i następne sprawdzenia wykona jeden
  `GameRoomBackground::Work` należący do tego otwarcia lobby.
- Istniejący timer jedynie rozpoczyna skończone zadanie lub odbiera gotowy
  wynik. Worker pobiera `latest_global_id`, a jeśli potrzeba — `global_entries`
  w tym samym zadaniu. Nie wywołuje `Tasks.run`, mowy ani `history.replace_entries`.
- Zachować obecny interwał, limit historii, deduplikację i zachowanie pierwszej
  próbki jako punktu odniesienia bez odczytywania starych zdarzeń. Pełną historię
  pobierać tylko na start lub po zmianie ID, bez zwiększenia liczby zapytań.
  Następny termin liczyć po zakończeniu próby, bez nadrabiania zaległych polli.
- Wynik do bieżącej kontrolki wprowadza timer UI, bez zmiany fokusu/kursora
  historii i ponownego czytania jej całości. Błąd pozostawia dotychczasowe dane.
  Po wyjściu `Work.close`; późny wynik nie odtwarza okna ani komunikatów.

**Ustawienia — `__app.rb#show_settings`,
`lib/game_room_screens.rb#Settings#wait`, `lib/table_watch_runtime.rb`.**

- Formularz powstaje od razu z lokalnych ustawień. Nie pobierać najpierw
  `table_watch_repository.load` przez `Tasks.run` bez aktywnego formularza.
- Pole subskrypcji ma stan `loading`, `ready` lub `unavailable`. Do `ready`
  nie można zaznaczać pozornej pustej listy; reszta kategorii działa normalnie.
- Wykorzystać istniejący `@table_watch_loader`/`GameRoomBackground::Work`:
  dodać stan wyniku i generację oraz jawne żądanie odświeżenia z Ustawień.
  Trwający odczyt startowy dla tego samego konta jest współdzielony, nie
  rozpoczynać równolegle drugiego. Po błędzie ponawiać tylko na wyraźne
  ponowne otwarcie, nie przy każdym Tabie lub tyknięciu timera.
- Wynik aktualizuje dane receivera, a otwarty formularz podmienia tylko pole
  subskrypcji, zachowując kategorię i fokus. Lista otrzymuje wynik raz;
  kolejne/spóźnione wyniki nie nadpisują zmian użytkownika. Zamknięty formularz
  nie dostaje callbacku, nawet jeśli skończony odczyt uzupełni cache usługi.
- Zapis przed ukończeniem odczytu lub po odmowie tabel zapisuje lokalne opcje,
  lecz nie dotyka nieznanych subskrypcji. `nil/error` nigdy nie oznacza `[]`.
  Zachować natychmiastowy osobny zapis makr i bieżącą obsługę częściowego
  błędu zapisu ustawień. Jawny zapis zmienionych preferencji serwerowych
  nadal musi uzyskać potwierdzenie — nie zgłaszać sukcesu z samego uruchomienia.

**Blokada — `lib/game_room_server_tables.rb`.**

- Obecny mutex cache/stanu dostępu przestaje obejmować `select/insert/update`.
  Dodać odrębny mutex operacji sieciowych; utrzymać ich dotychczasową
  serializację w workerach. Nie wywoływać sieci po prostu bez żadnej ochrony.
- Pod krótką blokadą pozostają cache uchwytów, odczyt/zapis stanu dostępu,
  numer generacji i `last_error`. `fetch` oraz `reset_access!` nie czekają na HTTP.
- `reset_access!` zwiększa generację. `check_access` i `perform` zapamiętują ją,
  ponownie sprawdzają przed żądaniem i publikują zmianę dostępu wyłącznie
  dla nadal aktualnej generacji. Stary błąd nie blokuje nowego konta/uruchomienia.
- Utrzymać rozróżnienie `stamp_required`, niedostępności i niewykonanego zapisu;
  zachować zwroty/wyjątki wymagane przez istniejących odbiorców.

Nie przenosić przy okazji kontroli aktualnego członkostwa po uruchomieniu
na niezależny, niezabezpieczony tor. Jest ona potrzebna przed wejściem
w kolejny stół i pozostaje z dotychczasową obsługą jednej instancji.

### 3.7. Pong i Audio Ball — wejście, lokalny ruch, potwierdzenie

Zmiany: `lib/realtime/task_ui.rb`, `lib/axel_pong/client.rb`,
`lib/axel_pong/peer_play.rb`, `lib/audio_ball/client.rb` oraz integracja
z oczekiwaniem `GameScreen`. Kontrolki `pong_surface.rb` i
`audio_ball_surface.rb` zachowują strażniki faktycznego fokusu.

1. **Jeden aktualizowany widok.** Przy oczekiwaniu na odczyt/zapis tej samej
   partii zachować podpięty formularz i obecny `GameRoomRealtime::Timer`.
   `attach_view` ma być idempotentne dla tej samej pary formularz/powierzchnia;
   prawdziwa zmiana widoku nadal odpina stary timer/wejście. `TaskUI` musi znać
   rzeczywisty formularz również wtedy, gdy przekazano adapter oczekiwania,
   zamiast porównywać tylko `options[:ui].equal?(@form)`. Nie wywoływać `frame`
   drugi raz obok timera ani z workera. Gdy widoku nie ma, dotychczasowa
   ścieżka utrzymania kanału bez wejścia pozostaje.
2. **HTTP nie jest pauzą gry.** Przy zdrowym kanale i ważnej bieżącej wymianie
   odczyt HTTP/czat nie ustawia automatycznie `@network_wait` dla aktywnego
   pola gry. Klient nadal przetwarza lokalne wejście, fizykę i zdarzenia.
   Czat/pomoc/inna scena nadal nie są źródłem sterowania. Nie zmieniać
   uzgodnionej pauzy gry zręcznościowej po rzeczywistym przejściu do innego okna.
3. **Paletka niezależna od gotowości wymiany.** W Pongu oddzielić warunek
   lokalnego ruchu od `healthy` i prawa do serwu/odbicia. Ruch jest dozwolony,
   gdy istnieje silnik/widok, aktualne prawo do własnej paletki i fokus pola,
   także podczas uzgadniania/zapisu punktu lub chwilowej utraty kanału.
   `playable_input`, `sample_pointer_input` i gałąź `PeerPlay#frame` korzystają
   z tego warunku dla ruchu; przy pauzie wywołują tylko istniejące
   `Engine#position`, nie `step`. Ta metoda przesuwa kontrolowane ludzkie
   paletki bez symulowania lotu, bramek i decyzji bota. Obserwator nie uzyskuje
   sterowania. Odebranie miejsca/zmiana epoki nadal natychmiast blokuje wejście.
4. **Bez udawania łączności.** Przy rzeczywistej utracie zgodności kanału
   piłka i serw nadal czekają; nie przewidywać obrony przeciwnika. Wysyłka
   pozycji pozostaje zastępowalna i ograniczona obecnym harmonogramem;
   po odzyskaniu wysyłamy bieżącą pozycję, nie kolejkę dawnych ruchów/kliknięć.
   Zachować reset liczników i konieczność puszczenia klawisza po pauzie.
   Zatrzymanie piłki przy zdalnej bramce w oczekiwaniu na autorytatywne
   rozstrzygnięcie nie jest błędem lokalnego UI i nie znika od tej poprawki.
5. **Wynik i audio.** Uzgodniona bramka korzysta z obecnej szybkiej prezentacji
   oraz deduplikacji. LiveSessions nadal zatwierdza wynik i kolejną wymianę;
   nie przyjmować wcześniejszego serwu. Nie zmieniać uzgodnionych przerw
   lektora/serwu. `Audio#update` już dopuszcza `step/edge` podczas pauzy —
   zachować to, bez nowego toru audio i bez odgrywania odgłosów zaległych ruchów.
6. **Audio Ball.** Zachować granicę konkretnego lotu oraz ostatnio naciśnięty/
   trzymany klawisz. Oczekiwanie na niepowiązane HTTP nie kasuje obrony
   aktywnego lotu; rzeczywiste blur/detach/reset partii nadal ją czyści.
   Nie uzbrajać obrony przed lotem i nie przenosić kliknięć do następnej piłki.

Nie zmieniać tolerancji obrony, kroków fizyki, routingu, P2P, retry/ACK,
rotacji serwujących, czasu na punkt ani profili botów.

### 3.8. Pozostałe granice i zakres wyłączony

- Lokalne formularze wyboru karty, koloru, pionka, kości lub opcji nie mają
  pobierać danych wyłącznie do nawigacji. Zatwierdzenie akcji idzie jednym
  wspólnym kontraktem z 3.4, a nie osobnymi asynchronicznymi implementacjami gier.
- Tworzenie/dołączanie do stołu, ustalenie aktualnego członkostwa, pobranie
  nowej listy stołów, odtworzenie/zapis partii i zmiany uprawnień wymagają
  wyniku serwera. Pozostawić skończone zadania i ich czytelny postęp/anulowanie;
  nie otwierać niepotwierdzonego stołu ani nie przełączać starego widoku w ciemno.
- Widget zachowuje ustalone świeże dane przy wejściu, brak żądań od strzałek
  i odświeżenie co 5 s tylko na widgecie. Ten punkt nie przywraca starego
  odczytu nieistniejącego stołu ani komunikatu „brak stołów” przed odpowiedzią.
- Nie przenosić zwykłych ruchów na Communications i nie dodawać spekulacyjnego
  zagrywania. Nie poprawiać ELTEN-a, routera ani połączenia całego komputera.
- Pomiary są lokalne i ograniczone: czas oczekiwania w kolejce, HTTP,
  przerwa aktualizacji UI/wejścia oraz czas trwałego potwierdzenia osobno.
  Nie zapisywać treści czatu, kart, tokenów i prywatnych identyfikatorów kont.

### 3.9. Kolejność implementacji i warunki przyjęcia

1. Dodać celowane regresje odtwarzające brak aktualizacji formularza,
   skasowanie nowszego szkicu i blokadę cache; zachować wyniki starego kodu.
2. Rozdzielić blokady tabel oraz odczyty lobby/ustawień. Sprawdzić limit jednego
   żądania, zamknięcie okna, zmianę konta i błąd bez wyzerowania preferencji.
3. Wprowadzić kontekst oczekiwania, bramki aktywacji powierzchni, cykl widoku
   i ochronę szkicu w partii/poczekalni. Wykorzystać obecną serializację runnera.
4. Podłączyć zachowany widok realtime i rozdzielenie lokalnego ruchu paletki.
5. Po każdym z etapów 2–4 wykonać celowaną regresję dotkniętych miejsc,
   następnie właściwą część macierzy żywych prób z sekcji 3.10. Dopiero po
   jej zaliczeniu przechodzić dalej; na końcu sprawdzić współdziałanie etapów.
   Bez ponawiania pełnego runnera.

Macierz opóźnień: 0/1/3/10 s, błąd przed wysyłką, odpowiedź zagubiona
po zatwierdzeniu, błąd/odmowa, anulowanie oraz późny wynik. Sprawdzić dalszą
grę po zakończeniu, a nie tylko poruszające się strzałki.

Wspólny UI: pojedyncza karta UNO, pakiet/joker Makao, pionek Chińczyka,
kostka Domino, rzut/zapis Farkle i Yahtzee, ruch na planszy, formularz odpowiedzi,
Scrabble z lokalnym szkicem oraz wieloetapowa oferta Monopoly. Obowiązkowo
powtórzony Enter, Tab do czatu/historii, F1/Ctrl+F1, Esc, zmiana języka tekstu,
sortowanie, ostatnia karta/koniec partii i zachowanie pozycji po odpowiedzi.
Legalne wołanie Makao podczas tury bota pozostaje osobną kontrolą regresji.

Czat: sukces/błąd, pisanie i kasowanie podczas wysyłki, skasowanie i ponowne
wpisanie identycznego tekstu, komenda ruchu, fokus i zaznaczenie, poczekalnia
i partia. Jedno potwierdzenie nie czyści ani nie wysyła następnej wiadomości.

Cykl życia: zmiana partii/obsady/gospodarza podczas oczekiwania, zamknięcie,
powrót obserwatora, pojedyncza instancja, widget, Ctrl+J i powiadomienia;
zwykła partia przykryta Wiadomościami/Konferencją i powrót bez utraty zdarzeń.

Realtime: singiel, debel, ludzie/boty/obserwator-gospodarz. Osobno opóźnienie
HTTP, osobno dostawy Communications, następnie obie sytuacje. Sprawdzić
klawiaturę i mysz, bieżącą obronę, brak serwu z czatu/pauzy, ruch paletki
podczas potwierdzania punktu, jeden dźwięk/wynik, przejście do kolejnej wymiany,
reconnect i rewanż. Symulowana kolejka pakietów nie jest pomiarem realnego pingu.

Rozszerzyć m.in. istniejące testy `game_screen_network_test`,
`game_session_screen_test`, `monopoly_staged_trade_screen_test`,
`surface_framework_test`, `server_tables_test`, `settings_table_access_test`,
`axel_pong_network_wait_test`, `axel_pong_chat_input_test`,
`audio_ball_input_boundary_test` i `audio_ball_defense_input_test`.
Dodać przypadki oczekiwania dla rodzajów powierzchni i szkicu, których obecne
testy nie obejmują. Dotychczasowy test neutralnego wejścia przy **odpiętym**
widoku nadal ma przechodzić; dodać osobno zachowany aktywny widok, nie usuwać
starego zabezpieczenia, aby sztucznie uzyskać pozytywny wynik.

Kryteria: zero dodatkowych ruchów/zapisów, brak zgubionego tekstu/fokusu,
jedna aktywna pętla realtime, brak rosnących handlerów/workerów i identyczne
autorytatywne rozstrzygnięcia. Sztuczne opóźnienie 10 s nie może oznaczać
10 s bez aktualizacji należącego do operacji formularza. Zapisać rzeczywiste
przerwy UI i ich porównanie z baseline, nie gwarantować arbitralnego FPS.

Na końcu prób usunąć własne stoły, sondy i spowolnienie. Oddzielić dowody
z handlerów od fizycznej klawiatury/odsłuchu oraz jeden komputer od wielu łączy.
Budowanie, podpis, wgrywanie wersji użytkowej, zmiana wersji/changelogu
i GitHub nie są częścią przygotowania tego planu.

### 3.10. Obowiązkowe próby na żywych klientach po wdrożeniu

Na polecenie użytkownika plan obejmuje szerokie testy regresji, nie tylko
odtworzenie zgłoszonej ścinki. Poniżej jest macierz wszystkich obecnie znanych
rodzajów wejścia, powierzchni i zmian stanu objętych przebudową. Nie oznacza
to obietnicy sprawdzenia każdej możliwej kombinacji zdarzeń. Nową odrębną
ścieżkę odkrytą podczas implementacji dopisać do macierzy przed zakończeniem
prac. To plan przyszłych prób, nie wykaz już uzyskanych wyników.

#### Organizacja i punkt odniesienia

- Użyć rzeczywistych kont i normalnych okien ELTEN-a. Dwie kopie do zwykłych
  partii, trzy do zastępstw i gospodarza-obserwatora, cztery do pełnego debla.
  Na wszystkich uczestniczących kopiach musi działać ten sam badany kod.
  Nie restartować ani nie aktualizować głównego ELTEN-a bez osobnej zgody.
- Najpierw zapisać zachowanie bieżącego kodu, potem powtórzyć porównywalne
  próby po każdym etapie. Obowiązkowo badać zwykłe szybkie połączenie:
  poprawa przy wolnej sieci nie może pogorszyć normalnej gry.
- Tworzyć własne stoły testowe, domyślnie prywatne. Publiczny stół tylko
  wtedy, gdy badana jest ścieżka discovery/widgetu; nie używać cudzych stołów.
  Przed próbami upewnić się, że nie przerywa się partii użytkownika.
- Wejścia przez Programy, widget, zaproszenia i inne okna wykonać natywną
  ścieżką interfejsu. Samo wywołanie wewnętrznego `join` albo ustawienie pola
  w pamięci nie zalicza testu danej ścieżki.
- Oddzielnie zapisać próby handlerami/MCP, fizyczną klawiaturą/myszą oraz
  odsłuch. Działający model nie dowodzi poprawnej mowy, a wywołanie handlera
  nie dowodzi braku gubienia krótkich naciśnięć. Niedostępnego rodzaju próby
  nie oznaczać jako zaliczonego.
- Każda gra korzystająca ze zmienionego wspólnego kodu ma przejść krótką
  próbę normalnej rozgrywki. Pełne przypadki graniczne wykonać dla każdego
  odrębnego rodzaju powierzchni oraz wyjątków wymienionych poniżej. W raporcie
  wymienić konkretne gry i warianty, nie zastępować ich określeniem „wszystkie”.

#### A. Sieć, oczekiwanie i zakończenie operacji

- Bez spowolnienia oraz z opóźnieniem 1, 3 i 10 sekund; także nieregularne
  opóźnienia. Osobno spowolnić gospodarza, gościa i obie strony.
- Osobno opóźnić HTTP przy działającym Communications, dostawę Communications
  przy działającym HTTP oraz oba kanały. Nie mylić oczekiwania na trwały zapis
  z pingiem relay ani z płynnością lokalnego formularza.
- Sprawdzić odmowę uprawnień, błąd przed wysyłką, utratę odpowiedzi już po
  zatwierdzeniu ruchu, timeout, ponowne połączenie i późną odpowiedź.
  Niepewny wynik nie może powodować drugiego zagrania, wiadomości lub punktu.
- Anulowanie podczas oczekiwania, odpowiedź po zamknięciu formularza oraz
  odpowiedź ze starej partii po rozpoczęciu nowej. Wynik nie może trafić do
  nowego widoku ani wskrzesić zamkniętego okna.
- Podczas oczekiwania naciskać Tab, strzałki, skróty odczytu, historię,
  głośność i pomoc. Kilkukrotny Enter lub przytrzymanie klawisza nie może
  kolejkować dodatkowych ruchów do wykonania po odpowiedzi.
- Każda próba kończy się sprawdzeniem zgodności zaakceptowanych zdarzeń
  i rewizji, a potem kolejną legalną akcją. Dla stanów prywatnych porównywać
  zgodność uprawnionych projekcji, nie oczekiwać identycznych rąk u graczy.
- Spowolnienie i wstrzykiwane awarie ograniczyć do testowanego Game Roomu,
  z wyłącznikiem i ograniczonym czasem działania. Nie zmieniać połączenia
  całego komputera, zegara systemowego ani ustawień serwera. Nie generować
  lawiny ponowień lub sztucznego ruchu w celu osiągnięcia limitu API.

#### B. Lobby, ustawienia i dostęp do tabel

- Otworzyć lobby, ustawienia i lokalne kategorie podczas wolnego odczytu
  serwera. Przejścia po kontrolkach i edycja lokalnych opcji mają działać.
- Subskrypcje: poprawne wczytanie, rzeczywiście pusta lista, brak uprawnień,
  błąd sieci, zamknięcie i ponowne otwarcie przed zakończeniem odczytu.
  Nieznanej listy nie zapisać jako pustej i nie nadpisać później nowych zmian.
- Zapis/anulowanie ustawień, zapis lokalnych opcji przed gotowością części
  serwerowej, natychmiastowy zapis makra. Brak tabel nie zamyka lokalnych opcji.
- Nakładające się odczyty ustawień i lobby oraz unieważnienie cache podczas
  żądania. Sprawdzić liczbę żądań i to, czy krótki odczyt cache nie czeka na HTTP.
- Spóźniony wynik po zmianie kontekstu aplikacji/konta nie zmienia bieżących
  uprawnień lub preferencji. Zmianę konta badać tylko na przygotowanej kopii
  testowej; nie wylogowywać głównego konta użytkownika.
- Przychodzące zaproszenie lub powiadomienie o stole w trakcie pisania,
  przeglądania lobby i oczekiwania na sieć: brak utraty tekstu i nowej ścinki,
  właściwe filtry i pojedynczy komunikat/dźwięk.

#### C. Zwykłe gry i rodzaje pól gry

- UNO: pojedyncza karta, dobranie, wybór koloru po obu kartach Wild, ostatnia
  karta, koniec rozdania i rewanż. Z/Shift+Z z jedną i kilkoma legalnymi kartami,
  sortowanie oraz istniejące reakcje poza własną turą tam, gdzie są dozwolone.
- Makao: zwykła karta, paczka Shift+Enter, wybór jokera, obrona i automatyczna
  kara. Wołanie Makao podczas tury bota nadal działa; sam namysł bota nie może
  blokować wszystkich działań gracza.
- Chińczyk: rzut, wybór spośród kilku pionków, pojedynczy możliwy ruch,
  dodatkowy rzut i zbicie. Po opóźnieniu nie wybiera się innego pionka wskutek
  zmiany indeksu lub ponownego wykonania naciśnięcia.
- Domino i Mexican Train: dobranie, kostka pasująca w kilka miejsc, wybór
  strony/pociągu, dublet oraz brak legalnego zagrania. Z zachowuje dotychczasową
  legalność i nie zatwierdza drugiej operacji w czasie pierwszego zapisu.
- Farkle i Yahtzee: rzut, wybór kości, ponowny rzut, bank/zapis kategorii,
  koniec tury i rozdania. Spóźniony wynik nie nadpisuje nowszego zaznaczenia.
- Plansze: wybór pola i ruch wieloetapowy w szachach/warcabach, ruch Reversi
  oraz gra ze stanem przechowywanym poza `Replay#state`, np. Czwórki.
  Sprawdzić kursor, prezentację planszy i zakończenie partii.
- Formularze odpowiedzi i prywatnych wyborów: Quiz, Państwa-miasta, Krowa
  i Taboo. Zatwierdzenie, anulowanie i upływ czasu nie mogą ujawniać sekretu,
  gubić wpisanego tekstu ani ponownie zatwierdzać odpowiedzi.
- Scrabble i Remik: lokalne układanie/zaznaczanie, cofnięcie, zatwierdzenie
  oraz aktualizacja od przeciwnika. Szkic i kolejność wybranych elementów
  nie mogą zmienić się od samego oczekiwania lub odświeżenia.
- Monopoly: normalny zakup, oferta wieloetapowa, anulowanie i ponowne otwarcie,
  oferta czterech nieruchomości za jedną, człowiek i bot. Po `trade_prepare`
  używać aktualnej rewizji; po ofercie musi działać dalsza tura.
- Karcianki z licytacją/lewami/wymianą, w tym Tysiąc, Spades i Poker, oraz
  Wojna/Wojna naukowa z jednoczesnym wyborem: sprawdzić przejścia faz,
  automat/bota i brak zatwierdzenia wyboru po zmianie jego kontekstu.
- Dla każdej odrębnej ścieżki sprawdzić legalną i nielegalną akcję, szybkie
  ponowienie Entera, zmianę fokusu w oczekiwaniu, odbiór ruchu przeciwnika
  oraz dalszą grę po odpowiedzi. Limity czasu, jeśli dostępne, sprawdzić
  również przy odpowiedzi sieciowej docierającej na granicy terminu.

#### D. Czat, historia, pomoc i fokus

- W poczekalni i podczas partii wysłać wiadomość, a przed potwierdzeniem
  dopisać, skasować lub wkleić następny tekst. Osobno skasować wszystko
  i ponownie wpisać identyczną wiadomość. Nowego szkicu nie wolno wyczyścić.
- Sukces i błąd wysyłki, ponowne naciśnięcie Entera, równoczesna wiadomość
  od drugiej osoby oraz komenda gry wpisana w czacie. Zachować polskie znaki,
  kursor i zaznaczenie; jedna próba nie wysyła automatycznie kolejnego szkicu.
- W trakcie oczekiwania przejść na rękę/planszę lub historię, zmienić pozycję,
  kategorię historii i sortowanie. Po odpowiedzi zachować najnowszy wybór,
  nie pozycję zapamiętaną przed wysłaniem. Jeśli element zniknął wskutek
  legalnego ruchu, zastosować dotychczasową regułę wyboru sąsiada.
- Początek/koniec rundy i partii podczas pisania oraz czytania historii:
  brak przeskoku na pole gry, utraty szkicu i powtórnego odczytu całego pola.
- F1, Ctrl+F1, skróty głośności i odczyty informacji podczas oczekiwania.
  Zamknięcie pomocy Esc nie anuluje przypadkiem operacji spod niej; kolejne
  Esc przechodzi zwykłą ścieżką pytania o opuszczenie/zamknięcie.
- Pomoc i czat nie sterują grą. Powrót do pola gry nie odtwarza Entera,
  kliknięcia ani przytrzymania pochodzącego z innej kontrolki.

#### E. Wejścia do aplikacji, inne okna i jedna instancja

- Osobno zimne i ponowne wejście: Programy, widget (stół, Ctrl+N, makro,
  Ctrl+J), Ctrl+J wewnątrz Game Roomu i zwykłe powiadomienie o zaproszeniu.
  Publiczny i prywatny stół; dołączenie jako gracz i obserwator.
- Ponowić te wejścia, gdy istniejący Game Room jest w lobby, przy stole,
  za Wiadomościami/Konferencją oraz w dialogu lub oczekującej operacji.
  Ma wrócić właściwa instancja, bez dodatkowego UI, członkostwa i wykonawcy.
  Zachować odmowę wejścia do drugiego stołu, gdy wymaga jej obecne zabezpieczenie.
- Po zimnym wejściu z widgetu odebrać prawdziwy ruch drugiego konta, także
  pod innym oknem. Sam udany `join` nie dowodzi poprawnego nasłuchiwania.
- Otworzyć Wiadomości, forum i Konferencję z głównej oraz dodatkowej sceny
  Game Roomu; przejście ma udać się za pierwszym razem. Wrócić do właściwego
  miejsca, również po odmowie opuszczenia stołu/zamknięcia aplikacji.
- Za innym oknem sprawdzić zwykłą partię i poczekalnię: dołączenie/wyjście,
  dodanie bota, rozpoczęcie, ruchy, koniec rozdania i rewanż. Potwierdzić
  odświeżenie, mowę i dźwięk jeszcze przed powrotem, zgodnie z ustawieniami.
- Sprawdzić wyłączoną/włączoną mowę i sygnał tury poza stołem, również gdy
  ELTEN nie jest na pierwszym planie. Po powrocie bez zaległej lawiny sygnałów.
  W realtime zachować świadomą pauzę po przejściu do innego okna; nie traktować
  tej macierzy jako zgody na nową obsługę gry lub obserwatora w tle.

#### F. Obsada, gospodarz i cykl życia stołu

- Człowiek zastąpiony botem, bot człowiekiem i gracz obecnym obserwatorem;
  odejście/powrót zastąpionej osoby. Nowy uczestnik widzi właściwą rękę/rolę,
  stary nie steruje jej dalej i nie zostaje błędnie wyrzucony do lobby.
- Jawne przekazanie gospodarza, jego wyjście, gospodarz będący obserwatorem
  oraz przejęcie istniejących botów. Sprawdzić ich następny rzeczywisty ruch.
- Gra bez botów, niedozwolone zastępstwo w prywatnej fazie oraz zmiana obsady
  podczas otwartego wyboru osoby. Zachować obecne ograniczenia, nie omijać ich
  w celu ukończenia testu i nie przypisywać sterowania według starego indeksu.
- Zmiana gospodarza, zastępstwo lub zakończenie partii podczas zapisu ruchu
  i czatu. Spóźniony wynik starego wykonawcy nie wykonuje akcji za nową osobę.
- Zwykłe wyjście, powrót obserwatora, zamknięcie dla wszystkich, odejście
  ostatniej osoby, ponowne utworzenie stołu i rewanż z innymi ustawieniami.
- Zapis/odtworzenie obsługiwanej gry: potwierdzony zapis przed zamknięciem,
  błąd zapisu bez utraty stołu, odtworzenie i następny ruch. Użyć tylko
  własnych próbnych zapisów, bez naruszania archiwów użytkownika.

#### G. Axel Pong i Audio Ball

- Pong: singiel dwóch ludzi i człowiek–bot; debel czterech ludzi, dwóch ludzi
  z dwoma botami oraz trzech ludzi z botem. Dodatkowo gospodarz-obserwator
  w obsadzie mieszczącej się w dostępnych kopiach. Nie zastępować pełnego
  debla ludzi samą symulacją czterech paletek w jednym kliencie.
- W deblu doprowadzić co najmniej do pełnego obiegu serwujących i jego
  powtórzenia. Sprawdzić pierwszy i kolejny serw tej samej osoby, obie drużyny,
  punkty ludzi i botów, koniec meczu oraz rewanż, także ze zmianą limitu punktów.
- Obrona krótko naciśniętym i trzymanym klawiszem, klawiatura i mysz,
  odbicia od bandy, zmiana kierunku paletki i punkty po obu stronach.
  Porównać pozycję piłki, rozstrzygnięcie i dźwięk z właściwej perspektywy.
- Opóźnić zapis bramki w HTTP: lokalna paletka nadal reaguje, lecz nowy serw
  czeka na wymagane potwierdzenie. Nie ma drugiego punktu, powtórnego audio,
  zaległego odbicia/serwu ani drugiej pętli fizyki.
- Opóźnić niezwiązany odczyt lub wysyłkę czatu podczas trwającej wymiany:
  zdrowe połączenie realtime i aktywne pole gry zachowują obsługę wejścia.
  Osobno rzeczywista utrata kanału, jego powrót i wznowienie bez popychania Enterem.
- Audio Ball: człowiek–człowiek i człowiek–bot, obie strony, obserwator;
  krótka próba każdego poziomu trudności, granice wejścia szczególnie przy
  szybkiej piłce. Sprawdzić ostatni wciśnięty/trzymany klawisz i sekwencje
  D–S–D, zwalnianie klawiszy oraz kilka trzymanych jednocześnie.
- Audio Ball: wejście podczas przygotowania, początku lotu i tuż przed
  rozstrzygnięciem. Zachować aktualny kontrakt obrony; nie przenosić reakcji
  z poprzedniej piłki i nie uzbrajać obrony z czatu/pomocy.
- Dla obu gier sprawdzić pomoc, ustawienia lokalne, czat, historię, utratę
  fokusu i powrót. Realtime poza własnym polem nie czyta cudzej klawiatury;
  obserwator nie steruje graczem, a jego perspektywa i dźwięki pozostają poprawne.
- Relay oraz dostępna natywna ścieżka P2P/mieszana: brak zmiany routingu przez
  tę przebudowę, właściwy opis Ctrl+F4 i działanie po powrocie z awarii.
  Niedostępnego P2P nie zaliczać na podstawie samego zaznaczenia opcji stołu.
  Jeden komputer nie potwierdza jakości połączeń między różnymi sieciami.

#### H. Współdziałanie punktów 1–2 i powtarzane przejścia

- Filtr 45 minut: własny stół aktywny, rzeczywiście bezczynny i oczekujący;
  widget i Dołącz pokazują zgodny wynik. Nieznany/stary znacznik nie ukrywa
  stołu. Aktywność przywraca widoczność, a ukrycie nie zamyka sesji ani nie
  blokuje bezpośredniego zaproszenia. Nie przestawiać globalnego zegara.
- Chińczyk: nicki/kolory na żywych ruchach, zbiciach, odczytach skrótami
  i w historii; po zmianie prezentacji i ponownym wejściu. Nie filtrować
  treści czatu ani nie zmieniać historycznych autorów po zastępstwie.
- Powtórzyć wejście/wyjście, przykrycie/powrót, pomoc i rewanż wiele razy,
  również naprzemiennie w różnych grach. Zaplanować dłuższą sesję zwykłej gry
  z okresowym spowolnieniem, nie tylko pojedyncze kilka sekund po hotloadzie.
- Sprawdzić czysty start oraz ponowne wczytanie aplikacji w tym samym procesie
  na kopii testowej. Liczba handlerów, timerów, workerów i kanałów nie narasta;
  zamknięte formularze nie odbierają wejścia ani nie publikują późnych wyników.

#### Raport, warunki zatrzymania i sprzątanie

Dla każdego przypadku zapisać: etap/kod, grę i wariant, role, ścieżkę wejścia,
rodzaj spowolnienia, oczekiwany i rzeczywisty wynik, metodę sterowania oraz
PASS/FAIL/BLOCKED/NOT RUN. Zachować pierwsze niepowodzenia. Błąd pomocnika,
brak drugiego konta lub niedostępne MCP to nie wynik pozytywny.

Mierzyć przerwy obsługi UI, czas akcji i potwierdzenia oraz liczbę rzeczywistych
żądań/ponowień. Porównać z punktem odniesienia bez spowolnienia i po jego
wyłączeniu. Do diagnozy wystarczają znaczniki operacji, rewizje i porównania
stanów w pamięci; nie utrwalać treści czatu, prywatnych rąk i poświadczeń.

Utrata lub podwojenie ruchu, rozbieżność rozstrzygnięć, zniknięcie szkicu,
serw/obrona z czatu, niedziałające odświeżanie po powrocie, dodatkowa instancja
albo nowa ścinka na szybkim łączu zatrzymują przyjęcie etapu. Naprawić przyczynę,
powtórzyć nieudany scenariusz i bezpośrednio zależne przypadki. Nie usuwać
zabezpieczeń ani zmieniać zasad/fizyki po to, aby test przeszedł. Etapy powinny
dać się wycofać osobno bez cofania wcześniejszych niezależnych poprawek.

Przed uznaniem zakresu za gotowy przedstawić również listę nieprzeprowadzonych
prób i granice dowodów. Braków w scenariuszach krytycznych nie ukrywać ogólnym
„testy przeszły”; wymagają uzupełnienia lub jawnego uzgodnienia ograniczenia.
Na końcu zamknąć wyłącznie własne stoły, usunąć własne próbne zapisy i sondy,
wyłączyć spowolnienie, sprawdzić opróżnienie jego kolejki oraz normalną dalszą
grę. Obecne polecenie dodaje tę macierz do planu — nie uruchamia testów,
wdrożenia, instalacji ani publikacji.

## 4. Warcaby — poprawne ustawienie planszy i numeracja pól

Stan: 27 września 2026 — potwierdzona lokalnie przyczyna zgłoszenia Tomka,
zakres zapisany do późniejszego wdrożenia. Bez zmian kodu produkcyjnego.

### Potwierdzony problem

- Na początku partii 100-polowej obecny kod i lista celów powierzchni
  proponują z pola 32 ruchy na 26 i 27, zamiast prawidłowych 27 i 28.
- Z pola 35 proponują 29 i 30, podczas gdy zwykły ruch białego pionka
  w tej pozycji jest możliwy tylko na 30. W zgłoszeniu występuje też 35→25:
  to również nie jest zwykły legalny ruch pionka i nie należy go dodawać.
- Algorytm zwykłego ruchu przesuwa pion o jedno pole po przekątnej.
  Problemem jest lustrzany względem standardu układ ciemnych pól w połączeniu
  z numeracją: przy białych na dole lewy dolny róg jest jasny zamiast ciemnego.
- `dark?` i `PLAYABLE_COORDINATES` w `games/checkers.rb` przyjmują nieparzystą
  sumę współrzędnych, podczas gdy widok ma początek wierszy na dole.
  `checkers_coordinate_label_sets` numeruje tak ułożone pola od góry,
  od lewej. `checkers_field_number` powiela tę numerację w historii.
- Mechanizm jest wspólny dla plansz 8×8, 10×10 i 12×12. Dotychczasowe testy
  potwierdzały nasz układ i liczbę ruchów, lecz utrwalały błędne położenie
  numerowanych pól. Nie traktować ich obecnego powodzenia jako zgodności
  z prawidłową planszą.

Punkt odniesienia dla 100 pól: [oficjalne przepisy FMJD](https://www.fmjd.org/docs/Annex_1.pdf),
punkty 2.4, 2.6, 2.8 i 3.4. Porównanie otwarcia wykonano lokalnie na
rzeczywistym modelu gry i jego specyfikacji powierzchni, z niezależnie
odtworzonym standardowym układem. To nie była próba na żywym stole.

### Zakres poprawki

1. Ujednolicić geometrię prezentowanej planszy, ciemne pola i numerację,
   tak aby sąsiedztwo numerów odpowiadało prawidłowym przekątnym. Nie dodawać
   wyjątków dla samych pól 32 i 35 ani nie przepisywać strategii bota.
2. Zapewnić zgodność planszy, wyboru źródła i celu, odczytu V, komunikatów
   błędów, bieżących zdarzeń oraz historii. Przełączenie na notację szachową
   i obrót widoku mają opisywać tę samą fizyczną pozycję i ruch; obrót nie
   zmienia tożsamości numerowanych pól.
3. Sprawdzić wszystkie trzy rozmiary, białe/czarne i obserwatora. Sama zmiana
   rozmiaru nie ma przy okazji zmieniać dotychczasowych opcji bicia, damki,
   promocji ani innych reguł gry.
4. Zgodnie z doprecyzowaniem użytkownika z 27 września pozostawić jeden
   poprawny układ, bez wersjonowania geometrii i gałęzi dla dawnych zapisów.
   Odtworzenie starych partii zapisanych według błędnych współrzędnych nie
   jest gwarantowane. Zachować zabezpieczenia bieżącej gry przed nielegalnym
   lub spóźnionym ruchem; rezygnacja ze zgodności nie oznacza ich usunięcia.

Miejsca do pracy: przede wszystkim `games/checkers.rb` (ustawienie początkowe,
`dark?`, `PLAYABLE_COORDINATES`, etykiety pól i historia) oraz celowane testy.
`games/board_game.rb` i `lib/game_surfaces/piece_board.rb` sprawdzić na granicy
mapowania współrzędnych; nie zmieniać wspólnych plansz innych gier, jeśli
poprawkę da się zamknąć w warcabach. Zasady/tłumaczenia korygować tylko wtedy,
gdy opisują zmieniane zachowanie.

### Weryfikacja przed przyjęciem poprawki

- Niezależny wzorzec numeracji i sąsiedztwa pól, nie oczekiwania wyliczone
  przez tę samą metodę, którą test sprawdza. Obowiązkowe regresje 32→27/28
  i 35→30 na początku partii 100-polowej; odrzucenie 32→26, 35→29 i 35→25.
- Pełna siatka pól dla 8×8, 10×10 i 12×12: skraje, oba kierunki ruchu,
  puste/zajęte cele, notacja liczbowa/szachowa i obie orientacje widoku.
- Bicia do przodu/do tyłu, wielokrotne i maksymalne bicie, blokowanie przez
  zbite piony, damki, promocja oraz kontynuacja ruchu bota. Sprawdzić, że
  korekta planszy nie znosi obowiązku bicia ani nie tworzy ruchów poza nią.
- Pełny/przyrostowy replay, odtworzenie oraz kolejny ruch w poprawnej
  geometrii. Stare pozycje testujące reguły lub jakość bota przenieść
  razem z ruchami, zachowując sens prób; nie przedstawiać tego jako
  potwierdzenia zgodności dawnych zapisów.
- Żywe próby na dwóch kontach dla każdego rozmiaru: otwarcie i dalsze ruchy
  obu stron, wybór strzałkami/Enterem, V, obrót i zmiana notacji, komunikaty
  oraz historia. Dodatkowo gra z botem i widok obserwatora. Potwierdzić
  zgodne cele i rozstrzygnięcia na obu kontach, nie tylko odczyt u gospodarza.
- Gdy dotknięty zostanie wspólny widok planszy, sprawdzić również jego
  pozostałych odbiorców. Wyniki lokalne, żywe handlery oraz fizyczne wejście
  i odsłuch raportować oddzielnie, zgodnie z sekcją 3.10.

Obecne polecenie oznacza zapisanie punktu w planie, nie wdrożenie, uruchomienie
żywych prób, przebudowanie paczki ani publikację.

## 5. Audio Ball — usunięcie szelestu z początku standardowego dźwięku up

Stan: 27 września 2026 — zapisane do późniejszego wdrożenia, bez edycji audio.

- Obciąć pierwsze **3 sekundy** nagrania `Audio/audio_ball_up.opus`
  (identyfikator `audio_ball_up`, standardowy pakiet dźwięków). Powodem
  jest zgłoszony niepożądany szelest na początku nagrania.
- Nie zmieniać `Audio/audio_ball_audiodisc_up.opus` ani pozostałych dźwięków
  pakietu Audiodisc. Nie przycinać przy okazji innych nagrań.
- Zachować nazwę/identyfikator zasobu, głośność, liczbę kanałów i pozostałe
  brzmienie. Jeżeli potrzebne jest ponowne kodowanie, korzystać z oryginału,
  jeśli jest dostępny, oraz obowiązującego formatu Opus. Nie normalizować
  ani nie ściszać dodatkowo pliku w ramach tej poprawki.
- Przy wdrożeniu sprawdzić długość nagrania i odsłuchać początek po cięciu,
  a następnie odtwarzanie górnej piłki w domyślnym pakiecie, także zapętlenie
  podczas dłuższego lotu. Potwierdzić brak zmiany pliku wariantu Audiodisc.
- To korekta nagrania, nie czasu lotu, poziomów trudności, obrony lub
  synchronizacji. Nie zmieniać tych mechanizmów przy okazji.

Obecne polecenie dodaje wyłącznie punkt planu; dźwięk i paczka pozostają
na razie bez zmian.

## 6. Lista osób przy stole — standardowe menu użytkownika ELTEN-a

Stan: 27 września 2026 — zapisane do późniejszego wdrożenia, bez zmiany kodu.

### Zachowanie

- Enter lub aktywacja osoby kliknięciem na liście użytkowników przy stole
  otwiera bezpośrednio standardowe menu tego użytkownika w ELTEN-ie.
- Dostępne mają być natywne czynności, m.in. dodanie/usunięcie z kontaktów,
  napisanie wiadomości prywatnej, zadzwonienie i wizytówka. Dokładną listę
  oraz dostępność akcji ustala ELTEN; nie kopiować tych funkcji do Game Roomu
  ani nie utrzymywać własnego, niepełnego odpowiednika menu.
- Działać ma jednakowo w poczekalni, podczas partii i po jej zakończeniu,
  dla rzeczywistych kont graczy, obserwatorów i gospodarza. Nie ograniczać
  dostępu do gospodarza stołu.
- Dla bota lub pustej listy nie wywoływać menu konta. Nazwa wylosowana dla
  bota nie jest loginem, nawet gdy brzmi identycznie jak nick człowieka.
- Dotychczasowe menu zarządzania stołem, Ctrl+M, Ctrl+Shift+R oraz akcje
  dotyczące botów pozostają bez zmian. Otwarcie menu osoby nie jest ruchem
  w grze ani poleceniem opuszczenia stołu.

### Podłączenie

- Użyć istniejącego `EltenAPI::Common#usermenu(user)` przez właściwy kontekst
  programu/UI. Natywna implementacja jest w źródłach hosta pod
  `src/eapi/common/user_menu.rb`; nie mylić jej z `Program#user_menu_options`,
  które służy do dodawania pozycji aplikacji do menu użytkownika.
- Wspólne podłączenie umieścić przy `GameRoomParticipantMenu.bind`
  (`lib/participant_menu.rb`). `__app.rb` i `lib/game_screen.rb` przekazują
  wywołanie natywnego menu; nie dopisywać osobnych handlerów do każdej gry.
- Login brać z `GameRoomLayout::Screen#selected_participant`, nie parsować
  tekstu wiersza zawierającego rolę, drużynę lub stan połączenia. Sprawdzić
  niepusty identyfikator i typ uczestnika przez `GameRoomParticipants`.
  Zapamiętać wybraną osobę przy aktywacji, aby późniejsze przesunięcie listy
  nie skierowało czynności do kogoś innego.
- Wiązanie ma obejmować wyłącznie listę osób; Enter w czacie, historii lub
  polu gry zachowuje swoją dotychczasową funkcję. Odświeżanie formularza
  nie może mnożyć handlerów ani otwierać menu dwukrotnie.
- Nie pobierać profilu podczas chodzenia strzałkami po osobach. Dane potrzebne
  menu pobiera natywna ścieżka dopiero po świadomej aktywacji użytkownika.
  Nie wykonywać menu ani jego kontrolek w workerze.
- Po zamknięciu menu wrócić do właściwej listy i zachować szkic czatu oraz
  wybraną osobę, jeśli nadal jest obecna. Otwarcie Wiadomości lub Konferencji
  korzysta ze standardowej nawigacji hosta; nie tworzy drugiej instancji
  Game Roomu. Zachować działanie zwykłych partii w tle i dotychczasowe
  ograniczenia sterowania realtime poza polem gry.

### Sprawdzenie

- Lokalnie: poprawny login mimo opisów wiersza i zmian kolejności, gracz,
  obserwator, gospodarz, bot o nazwie podobnej do loginu oraz pusta lista.
  Jedno wywołanie po Enterze/kliknięciu, także po wielokrotnych odświeżeniach.
- Na dwóch rzeczywistych kontach: menu w poczekalni, aktywnej i zakończonej
  partii; zamknięcie Esc, otwarcie wiadomości do wskazanej osoby i powrót.
  Potwierdzić obecność natywnych opcji kontaktów/rozmowy, gdy host je udostępnia.
  Nie kontaktować się z osobami spoza testów w ramach weryfikacji.
- Pod menu i nad otwartymi Wiadomościami sprawdzić dalsze zdarzenia zwykłej
  partii, fokus i szkic po powrocie. W Pongu/Audio Ballu aktywacja/zamknięcie
  menu nie może wywołać serwu lub obrony. Zachować dotychczasową obsługę
  pozostałych skrótów listy uczestników oraz zakres pomocy F1.

Na tym etapie tylko dopisanie do planu — bez wdrożenia, żywych prób i paczki.

## 7. Ctrl+W — odczyt obsady wybranego stołu

Stan: 27 września 2026 — zapisane do późniejszego wdrożenia, bez zmiany kodu.

### Zachowanie

- Ctrl+W na zaznaczonym stole działa w dwóch miejscach: na liście stołów
  widgetu na ekranie głównym ELTEN-a oraz w „Dołącz” po wybraniu gry.
- Obecne nazwy i krótkie opisy wierszy obu list pozostają bez zmian.
  Nie dopisywać do nich obsady ani nie odczytywać jej przy wejściu Tabem,
  chodzeniu strzałkami lub automatycznym odświeżaniu. Rozszerzony odczyt
  graczy i obserwatorów następuje wyłącznie na żądanie pod Ctrl+W.
- Skrót pobiera aktualną obsadę bez dołączania i odczytuje ją bez otwierania
  dodatkowego okna, np. „Gracze: peterman, papierek, Jola. Obserwatorzy:
  ktośtam”. Sekcję obserwatorów pomijać, jeśli rzeczywiście nikogo w niej
  nie ma. Graczy podawać najpierw, obserwatorów potem.
- Boty wymieniać wśród graczy pod ich zwykłymi imionami. Gospodarza nie
  dopisywać automatycznie do graczy: może sam obserwować. Podział podczas
  partii ma odpowiadać jej rzeczywistej obsadzie po zastępstwach, nie tylko
  ustawieniu udziału w następnej grze. Nie powielać osoby w obu grupach.
- Zachować zaznaczony stół, fokus i zwykłe zachowanie Entera. Skrót jest
  lokalny dla tych dwóch list, nie dla całego ELTEN-a ani pola gry.
- Gdy lista jest pusta, stół już zniknął lub obsada nie jest udostępniona,
  podać krótki właściwy komunikat. Błędu odczytu i nieznanych ról nie
  przedstawiać jako pustej listy graczy lub braku obserwatorów.

### Źródło danych i podłączenie

- Natywne `DiscoveredSession#refresh` odświeża wybrany stół bez dołączenia,
  zajmowania miejsca lub przedłużania życia sesji. Jego `participants`
  zawiera identyfikatory i loginy, ale nie role z gry ani boty. Wartość
  `nil` oznacza niedostępność, a nie pustą obsadę. Potwierdzenie kontraktu:
  źródła hosta `src/eapi/live_sessions.rb` i `docs/eltenapps.md`.
- Obecne `TableSnapshot` dla odkrytego stołu nie gwarantuje pełnej listy
  osób i obserwatorów. Nie odczytywać jego zastępczej listy z samym
  gospodarzem jako dokładnej obsady. Nie używać `join_table_snapshot`
  ani chwilowego dołączania i wychodzenia w celu zdobycia tych danych.
- W `lib/live_session_store.rb` zaplanować wspólny odczyt obsady odkrytego
  stołu. W `publish_discovery`/`compact_discovery` uzupełnić techniczne
  metadane discovery, niewyświetlane w opisie wiersza, o minimalną
  informację o rolach obecnych ludzi i nazwach botów, wyliczoną
  z tej samej projekcji co lista uczestników stołu. Natywna lista osób
  pozostaje źródłem obecności kont; nie powielać niepotrzebnie loginów.
- Opis obsady aktualizuje gospodarz przy zmianie członkostwa, ról, botów,
  zastępstwach oraz rozpoczęciu/zakończeniu partii. Uwzględnić przejęcie
  publikacji po zmianie gospodarza. Nie dodawać żądania przy każdym ruchu
  ani drugiego stałego odpytywania. Wykorzystać istniejącą publikację ze
  sprawdzaniem zmian i ponowieniem po nieudanym zapisie.
- Discovery ma limit 1024 bajtów obejmujący także dotychczasowe ustawienia
  stołu i dane kontroli gospodarza. Sprawdzić rzeczywisty rozmiar całego
  opisu z najdłuższymi nazwami i pełną obsadą; dobrać zwarty zapis ról.
  Nie usuwać ustawień lub zabezpieczeń, nie psuć tworzenia stołu i nie
  przedstawiać obciętej obsady jako kompletnej. Przy braku miejsca lub
  niewystarczających danych starego stołu uczciwie zgłosić niedostępność.
- Nie ujawniać obsady prywatnego stołu ani omijać `hide_participants` przez
  dodatkowe publiczne metadane. Gdy podgląd osób jest ukryty, go nie
  publikować. Niezgodnych list członkostwa i opisu ról nie łączyć przez
  zgadywanie, że osoba o nieznanej roli jest graczem.
- Wspólną metodę udostępnić przez `lib/lobby_repository.rb`; formatowanie
  komunikatu współdzielić między oboma widokami. W `__app.rb` podłączyć
  ją do `show_tables_for_game` i przekazać do `GameRoomWidget::TableList`
  (`lib/game_room_widget.rb`). Dodać Ctrl+W do właściwej pomocy F1.
- Pobieranie wykonać poza wątkiem UI, zgodnie z punktem 3. Jedno żądanie
  naraz dla danego widoku; przytrzymanie skrótu nie tworzy kolejki zapytań.
  Zapamiętać tożsamość stołu i generację widoku, nie sam numer wiersza.
  Spóźniony wynik po zmianie zaznaczenia, opuszczeniu listy lub zamknięciu
  widoku nie może zostać odczytany jako obsada nowo wskazanego stołu.
- Zachować dotychczasowe odświeżanie widgetu: wejście, R i co 5 sekund tylko
  podczas obecności na nim. Strzałki nie pobierają obsady. Ctrl+W sprawdza
  wyłącznie wybrany stół, nie wszystkie stoły i nie otwiera Game Roomu.

### Sprawdzenie

- Lokalnie: dwie grupy, brak obserwatorów, gospodarz-obserwator, nazwane
  boty, zamiany ról, polskie znaki, pusta i niedostępna lista, stare dane
  oraz limit rozmiaru opisu. Sprawdzić brak podwójnych przypisań klawisza,
  niezmienione etykiety stołów i brak rozszerzonego odczytu bez Ctrl+W.
- Na własnych żywych stołach, z graczami i obserwatorem: oba miejsca
  odczytu, poczekalnia i partia, dołączenie/odejście, dodanie/usunięcie bota,
  zastępstwo i nowy gospodarz. Wynik porównać z rzeczywistą listą osób.
  Potwierdzić, że samo Ctrl+W nie dodaje członkostwa, zdarzenia dołączenia
  ani drugiej instancji Game Roomu.
- Przy wolnej sieci: dalsze działanie strzałek/Tab, zmiana zaznaczenia,
  zamknięcie listy, zniknięcie stołu i wielokrotne Ctrl+W. Sprawdzić brak
  spóźnionych odczytów oraz respektowanie niedostępnego podglądu uczestników.

Na tym etapie tylko dopisanie do planu — bez wdrożenia, żywych prób i paczki.
