# Instrukcje dla agentów pracujących nad ELTEN Game Room

## Bieżący kontrakt — czytaj przed historycznymi wpisami

- Źródła wymagają ELTEN 3.0.4; stan integracji opisuje
  [ELTEN_3_0_4_TABLES_PLAN.md](docs/ELTEN_3_0_4_TABLES_PLAN.md).
- Zasady utrzymania: [ARCHITECTURE.md](docs/ARCHITECTURE.md), bieżące porządki
  [MAINTAINABILITY_CLEANUP.md](docs/MAINTAINABILITY_CLEANUP.md) oraz dalsze
  czternaście punktów [MAINTAINABILITY_FOLLOWUP.md](docs/MAINTAINABILITY_FOLLOWUP.md).
  Historia i uzasadnienia są w [WORK_HISTORY.md](docs/WORK_HISTORY.md), nie są poleceniem cofania kodu.
- LiveSessions jest jedynym backendem stołów/ruchów. Nie przywracać dawnych
  tabel ani Signals. Tabele Krowy/lobby/rejestru/subskrypcji nadal są potrzebne.
- Zachować oba zabezpieczenia starego zamknięcia, epoki obsady, niezmienność
  historii, uzgadnianie niepewnych zapisów i ochronę prywatnych faz.
- Zwykła partia ma jednego wykonawcę, planowanie poza blokadą zapisu, ponowną
  walidację przed zapisem i most prezentacji na aktywnym wątku UI. Realtime
  ma osobną pętlę. Nie dodawać pracy UI/klawiatury do workera ani pollingu.
- Nie przywracać drugiego schedulera botów w `GameScreen`: gry turowe
  wykonuje `GameRoomSessionRunner`, boty realtime ich własny klient. Testy
  zapisu i potwierdzania ruchów bota muszą przechodzić przez aktywnego wykonawcę.
- Cofnięcie zamrożenia nieudanego zapisu wymaga potwierdzenia własnej granicy,
  tej samej partii i aktualnego gospodarza. Nie odblokowywać nowszego zapisu.
  Przyjęcie zaproszenia i zwykłe wyjście współdzielą ochronę przekazania
  prywatnej fazy i ponawiają ją tuż przed zwolnieniem obecnego stołu.
- Kolejność partii wynika z `__stack_sequence`, nie z losowego identyfikatora.
  Zdalny obserwator Ponga prezentuje pełne snapshoty, bez odtwarzania od zera
  historii odbić, której nie otrzymał. Nadal weryfikuje nadawcę i epokę.
- Błąd programu nie jest rozłączeniem: zachować diagnostykę i zatrzymać
  ponawianie wadliwej akcji. Celowy fallback ma być jawny i ograniczony.
- Cache prezentacji nie może pomijać zdarzeń ani dzielić mutowalnych modeli;
  sprawdzać również `nil` stanu w grach planszowych, obsadę i nowe sesje.
- Trening/eksperymenty umieszczać poza runtime w `tools/`. Testy współdzielą
  pomocniki z `test/support/`, nie scenariusze innych `*_test.rb`.
- Testy hosta korzystają z jednego `ELTEN_HOST_SOURCE`. Brak zależności,
  pominięcie lub timeout nie oznacza sukcesu. Po pierwszym pełnym przebiegu
  użytkownik polecił dalsze testy tylko zmienionych przypadków (25 września).
  Nie powtarzać teraz całego runnera. Dla dalszych czternastu punktów użytkownik
  zatwierdził próby żywych klientów i wczytanie kodu do pamięci, nie instalację,
  nową paczkę lub publikację. Nie rozszerzać tej zgody na inne operacje.
- Historyczne aplikatory quizu domyślnie nie zapisują. Wymagają zatwierdzonego
  manifestu wejść/celów i nie mogą cofać wersji. Nie powtarzać odsiewania
  pytań ani zmieniać audio/baz w ramach porządkowania kodu.

## Granice po dalszym audycie utrzymywalności

- Walidator historii jest czysty: indeksuje wyłącznie wcześniejsze zaakceptowane
  początki partii. Po zmianie uporządkowanych rekordów ponownie sprawdza historię;
  nie uznawać odrzuconego lub późniejszego początku za uprawnienie do ruchu.
- Retencja nieaktywnych stołów nie usuwa aktywnej sesji, operacji w toku ani
  nieuzgodnionego zapisu. Przy callbacku i publikacji walidacji sprawdzać tożsamość
  sesji/kolekcji pod blokadą: powtórzony licznik nie dowodzi tej samej generacji.
- Edytor opcji i wiązania skrótów mają osobne odpowiedzialności. Nie dopisywać
  do nich zapisu ruchów ani drugiego wykonawcy sesji. Reguły faz, lokalne opcje
  i efekty dźwiękowe deklaruje gra, zamiast nowej listy ID w szkielecie.
- Klient realtime resetuje własne pola; wspólny kod zarządza cyklem kanału,
  pingiem i sekwencją zapowiedzi, nie wspólną fizyką. Testować zastępstwo gracza,
  gospodarza-obserwatora, zamknięcie starego kanału i ponowną rejestrację pingu.
- Symulacja strategii jest leniwa. Nowa strategia bez deklaracji nadal dostaje
  dotychczasowy kontekst; rezygnacja z symulacji wymaga jawnego kontraktu.
  Porównywać wybrane akcje, ich kolejność oraz dalszy stan RNG, nie sam wynik gry.
- Odczyt kandydatów rejestru/subskrypcji używa ograniczonego snapshotu tabeli:
  do 15 s i 4096 wierszy, bez zapytania dla pustej listy. Własne ustawienia czytać
  świeżo, po zapisie unieważniać cache również przy niepewnym wyniku. Błąd nie
  oznacza pustych preferencji. Nie wymyślać operatora grupowego API ani żądania
  dla każdego użytkownika; zmiany innych kont mają jawne opóźnienie do 15 s.
- Pomocniki testów nie uruchamiają cudzych scenariuszy przy imporcie. Agregaty
  binarne izolują scenariusze, a raport nie liczy ich dzieci ponownie jako
  niezależnego dodatkowego pokrycia. Pierwsze niepowodzenia zachowywać osobno.

## Sposób pracy

- Wieloetapowy formularz, który najpierw zapisuje akcję pomocniczą, musi
  przekazać nowy replay i rewizję do dalszej obsługi tego samego formularza.
  Nie usuwać kontroli `StaleView` ani dopuszczać zapisu ze starego widoku.
  Regresja: `monopoly_staged_trade_screen_test.rb` (także anulowanie,
  ponowne otwarcie, człowiek/bot i dalsza tura). Zwykłe modalne wybory,
  które nie zapisują pośredniego zdarzenia, nie wymagają takiego obejścia.
- Po zastąpieniu uczestnika bot analizuje projekcję historii według obecnych
  miejsc przez `GameRoomParticipantDecisionEvents`; niezmienny zaakceptowany
  log i historyczne komunikaty zachowują dawnych autorów. Testować pełny
  i przyrostowy planer oraz dalszy stan RNG. Cache historycznej prezentacji
  uwzględnia cały prefiks zdarzeń, opcje i obsadę, nie tylko liczbę/ostatnie ID.
- Nie rozwijać wszystkich kandydatów ruchu tylko po to, by ustalić wykonawcę
  lub zbudować ekran. Zawężenie listy prezentacji nie może zawężać decyzji
  bota ani prawdziwych legalnych ruchów. Błąd odczytu członkostwa nie oznacza
  odejścia wszystkich osób; zachować błąd zamiast zwracać pustą listę.
- Prywatne odpowiedzi koordynować między instancjami tego samego natywnego
  Programu współdzielącymi plik. Usunięcie słowa Krowy musi przetrwać replay:
  znacznik dodania wiązać ze źródłowym zdarzeniem, nie sumą całej sesji.
- Zmianę gospodarza i zastępstwo sprawdzać ponownie na granicy zapisu,
  nie tylko przed otwarciem wyboru osoby: w czasie dialogu bot lub człowiek
  może zatwierdzić prywatny wybór. Zastępstwo rozróżnia konkretną osobę
  od cudzych oczekujących sekretów; nie znosić ochrony wszystkich prywatnych faz.
  Skróty podsumowujące wcześniejsze lewy lub bitwy korzystają z historycznych
  komunikatów, nie z nazw obecnej obsady. Gry z jednoczesnymi decyzjami
  deklarują `required_decision_key`, zamiast omijać ustawienia własnym `ding`.

Własne okna aplikacji używają `GameRoomUI::Form` lub
`GameSurfaces::RefreshAwareForm` z referencją `program:`. Wspólny szkielet
zapewnia lokalne F1 jako tekst tylko do odczytu oraz F2/F3 i Shift+F2/F3
do głośności. Historia używa GameRoomHistory::View, a nawigacja
GameRoomHistory.bind; index/check to pozycje znaków, entry_index to wpis.
Nie dubluj tych klawiszy w klasach gier, nie zmieniaj źródeł ani zapisanych
QuickActions ELTEN-a. Dynamiczną pomoc gry i pokoju aktualizuj przez te same
definicje co rzeczywiste skróty (`GameRoomContextHelp`), nie dopisuj na stałe
tipsów zależnych od fazy. Szczegóły: `docs/VOLUME_AND_HELP_224.md`.

- Najpierw odtwórz problem i wskaż warstwę, która jest jego właścicielem.
- Działający model za Wiadomościami/forum NIE dowodzi bieżącej mowy/audio.
  Prezentację przykrytej gry obsługuje GameRoomBackgroundPresentation na
  aktywnym wątku UI, w runtime właściwej aplikacji; worker tylko publikuje
  skopiowane dane. Nie aktualizować formularza gry ani klawiatury z tej
  ścieżki. Zachować wspólne kursory zdarzeń/czatu, kolejkę dźwięków,
  nieprzerywającą mowę i deduplikację po powrocie/rewanżu. ID sesji są
  losowe, nie monotoniczne. Rejestracje sprzątać przy zamknięciu, most
  hosta ma przeżyć reload bez closure starej aplikacji i bez narastania.
  Żywy test wymaga potwierdzenia wyjścia mowy ORAZ działającego audio
  jeszcze za natywnym oknem, nie tylko porównania stanów po powrocie.
  Regresje: game_background_presentation_test i game_background_native_input_test;
  szczegóły docs/BACKGROUND_GAME_EXECUTION.md.
- Gry turowe wykonują polityki automatyczne i boty przez wspólny
  GameRoomSessionRunner zarówno z widocznym, jak i przykrytym formularzem.
  Nie dodawaj drugiej pętli automatów w klasie gry lub GameScreen.
  Model/polityki nie mogą wołać UI, mowy, loop_update ani czytać kontrolek.
  Planowanie jest poza blokadą zapisu; przed zapisem trzeba dostarczyć
  gotowe callbacki i sprawdzić aktualną sesję/rewizję. Nie blokuj nim UNO
  interception, Makao ani czatu. Niestandardowy konstruktor zachowaj w
  build_session_game, szkic oznacz automatic_surface_identity, a wyjątki
  równoległego wejścia zawęź przez concurrent_session_input? do jednej
  rundy/fazy/operacji. Reguły nadal sprawdza action_for. Nie przenoś
  całego GameScreen lub game_client do Thread.new. Realtime ma własny
  lifecycle i session_runner? false. Przy zmianach testuj wiele instancji,
  backoff/niepewny zapis, powrót, deadline, freeze/rewanż i zakończenie.
  Testy: game_session_runner*_test.rb i game_session_screen_test.rb.
- Uruchomienie nad Konferencją może umieścić Game Room na równoległym wątku
  UI. Nie zakładaj, że działający protokół LiveSessions oznacza dostarczenie
  callbacków aplikacji. Własne okna muszą używać wspólnego Form z `program:`;
  nie zastępuj lokalnego, ograniczonego dispatchu globalnym tickiem, pętlą
  sieciową lub odpytywaniem serwera. Sprawdzaj uruchomienie główne i równoległe,
  powrót z innego okna, boty, rewanż oraz niezmienność szkicu/fokusu czatu.
  Regresje: test/parallel_scene_events_test.rb i parallel_scene_native_test.rb;
  `ELTEN_HOST_SOURCE` ma wskazywać źródła pasujące do badanego hosta.
- Rozszerzenie przypięte do globalnego obiektu hosta przeżywa aktualizację
  aplikacji bez restartu ELTEN-a. Znacznik „już zainstalowano” nie może
  pozostawiać closure ze starą przestrzenią aplikacji lub formatem danych.
  Przy takich zmianach testuj starą paczkę -> nową w jednym procesie,
  również powtórne przeładowanie, brak narastania wrapperów i odtwarzania
  starego wejścia. Czysty start i samo binarne wczytanie tego nie sprawdzają.
  Regresja Audio Balla: `test/audio_ball_keyboard_reload_test.rb`.
- `Replay#state` jest opcjonalne: Kółko i krzyżyk oraz Czwórki przechowują
  pozycję w polach `board`/`players` i zwracają `state: nil`. Wspólne hooki
  nie mogą wymagać Hasha stanu; opcje partii pochodzą również z ActionContext.
  Przy ich zmianach testuj prawdziwy replay klas gier, nie tylko sztucznie
  zbudowany Hash. Regresja opóźnienia botów: `test/bot_delay_replay_test.rb`.
- Kodowanie tekstów UI sprawdzaj również w paczce: ELTEN może wczytać źródła
  jako ASCII-8BIT, a brak tłumaczenia w `_()` pozostawia taki tekst bez zmiany.
  Nawet angielska etykieta z myślnikiem „—”, znakiem „×” lub innym znakiem
  spoza ASCII może wtedy wywołać Encoding::CompatibilityError przy doklejeniu
  przez kontrolkę polskiego/rosyjskiego opisu roli lub stanu. Teksty i etykiety
  przekazywane do kontrolek oraz składane komunikaty normalizuj do UTF-8 przez
  `GameRoomContent.utf8`, przed łączeniem/formatowaniem. Nie zmieniaj ID,
  wartości opcji ani binarnych danych, nie nadpisuj globalnego gettext ani
  kontrolek ELTEN-a i nie maskuj problemu usuwaniem znaków diakrytycznych.
  Etykiety `OptionDefinition` i `OptionChoice` normalizuje wspólny szkielet;
  nowe ustawienia mają go używać. Test musi przejść przez rzeczywiste
  tworzenie formularza i odczyt fokusu/stanu, także brakujące tłumaczenie
  Game Roomu obok tłumaczenia hosta. Nie wymuszaj UTF-8 w atrapach `_()` lub
  kontrolek, jeśli host tego nie robi — ukrywa to regresje. Używaj
  `test/game_option_encoding_test.rb` (źródła binarne; EN, PL oraz angielski
  tekst z rosyjskim hostem), a przy kolejnym pakowaniu także argumentu
  ze ścieżką gotowej paczki. Sam zwykły `require` albo test wyłącznie PL
  nie wystarcza do potwierdzenia zgodności.
- Tasowanie musi być zgodne z ELTEN-em: host nadpisuje `Array#shuffle`
  i `shuffle!` metodami bez argumentów. Nie używaj ich w kodzie partii ani
  planerów, zwłaszcza `shuffle(random: ...)`. Dla nowych wywołań stosuj
  `GameRoomRandom.shuffle(values, random: Random.new(seed))`, przekazując
  wspólne ziarno zapisane w zdarzeniu, nie nowy losowy seed podczas replaya.
  Zachowuj istniejące deterministyczne pomocniki (`CardGame#shuffled_cards`,
  `GameRoomDominoTiles.shuffle`, pomocniki planerów) i ich konwersję ziarna;
  nie migruj starych gier przy okazji, jeśli zmieniłoby to zapisane partie.
  Nie naprawiaj zgodności usunięciem argumentu random, `srand`, globalnym
  `rand` ani zmianą klasy Array w działającym ELTEN-ie. Testuj z
  `test/support/elten_array_shuffle.rb`, kontrolując rozdanie, ponowne
  tasowanie/wymianę, replay oraz kolejne użycie tego samego RNG. Sam test
  na zwykłym Rubym poza hostem nie wystarcza. Przy pakowaniu uruchom również
  binarne wczytanie z tą symulacją API; źródła i gotową paczkę rozróżniaj.
- Wprowadzaj małe, spójne poprawki i dodawaj celowany test regresji.
- Korzystaj z nowego, event-driven API ELTEN-a. Nie pisz ręcznych pętli UI.
- Rozszerzaj wspólny szkielet, gdy zachowanie jest wspólne dla rodziny gier;
  nie kopiuj tej samej obsługi do wielu klas gry.
- Nie przenoś reguł gry do `GameScreen` ani szczegółów interfejsu do transportu.
- Nie omijaj `action_for`, `GameRepository` i odtwarzania zdarzeń.
- Nowe karcianki mają korzystać ze wspólnej obsługi ręki, nie kopiować kursora:
  stabilne, unikalne ID kart, `hand_order` w faktycznej kolejności dobierania
  oraz `hand_epoch` identyfikujące właściciela i rozdanie. Szczegóły są w
  `docs/CARD_HAND_CURSOR_213.md`. Innych list, plansz i kości nie oznaczać jako
  ręki; ich zachowanie i odczyty nie mogą być zmieniane przez ten mechanizm.
- Nowa gra z rzeczywistą ręką kart implementuje `playable_card_navigation` i
  grupuje wszystkie legalne akcje według stabilnego ID fizycznej karty. `Z` i
  `Shift+Z` zapewnia wspólny szkielet. Automatyczny ruch wolno oznaczyć tylko,
  gdy karta nie wymaga dalszego wyboru, deklaracji, meldunku ani pakietu.
- Ręczne sortowanie ręki udostępnia `hand_sorting_available?` i wspólne
  `hand_sort_shortcuts`. Karty dostarczają semantyczne `sort_keys` dla
  colour/number/none, nigdy tłumaczone etykiety jako klucz. Domyślnego
  układu nie zmieniać przy samym dodaniu tej możliwości. Sortowanie widoku
  nie sortuje stanu partii, paczki ani kolejności zaznaczania układu;
  kontrolki CardTable/PacketCardSurface zachowują fizyczne ID i kursor.
  Sprawdzać konflikty skrótów i faktyczną obecność ręki na danym ekranie.
- Trwałą eliminację udostępnia `eliminated_from_game?`, oddzielnie od
  końca rundy, pasa, rozłączenia i all-in. Wspólny selektor dźwięków
  wykrywa przejście do tego stanu i respektuje ostateczny wynik/remis.
  Nie odtwarzać ponownie efektu porażki na końcu ani podczas replaya.
- Niezależne skutki jednego ruchu mogą mieć równoczesne efekty audio.
  Zbierać je niezależnie, nie przez wzajemnie wykluczające if/elsif;
  zachować deduplikację zdarzeń, akceptację ruchu i głośność gry.
- Tekst zasad ze znakami spoza ASCII tłumaczyć lokalnym
  `GameRoomRules.translate`: słownik hosta może przechowywać binarne klucze
  MO. Samo istnienie tłumaczenia i UTF-8 wyniku nie dowodzi, że klucz się
  dopasował. Testować rzeczywisty słownik albo wierną atrapę binarną.
- Bot wybiera akcję, ale wykonuje ją przez standardową ścieżkę gry.
- Stan stołu i partii synchronizuje stos LiveSessions. Publiczne stoły wyszukuj
  przez discovery i dołączaj do nich bezpośrednio; nie przywracaj bootstrapu
  ani synchronizacji przez Signals.
- Unikaj okresowego odpytywania i pełnej odbudowy formularza. Aktualizacja nie
  może przesuwać fokusu ani powodować zbędnych komunikatów czy dźwięków.

## Gry czasu rzeczywistego — opóźnienia i Communications

- Zapowiedź głosowa nie jest potwierdzeniem gotowości sieciowej. W Pongu
  nie uzależniaj serwu od końcowego znacznika syntezy u któregokolwiek gracza
  ani nie dodawaj po nim kolejnej pauzy: obowiązuje zwykły termin jak w singlu.
  Test z atrapą, która sama podaje końcowy indeks, nie sprawdza niezawodności
  rzeczywistego syntezatora. Uwzględniaj także całkowity brak tego indeksu,
  przerwanie mowy i różne wyjścia syntezy. Patrz `docs/PONG_SERVE_PAUSE_235.md`.
- Korzystaj ze wspólnego `Channel`/`EventChannel`. Przed implementacją
  rozpisz całą drogę akcji: wejście, kolejka, relay, odbiór, zastosowanie
  i prezentacja. Ustal, kto ma prawo rozstrzygać każde zdarzenie.
- Opcjonalne P2P Ponga/Audio Balla korzysta z natywnego `p2p: :full` i
  `p2p_participants_limit`, nie z własnych gniazd lub dodatkowego pośrednika.
  Zachowaj relay po wyłączeniu, ustawienie po reconnect/zmianie gospodarza
  i limit obejmujący obserwatorów (domyślnie 8, 0 bez limitu). Nie zmieniaj
  globalnej zgody ELTEN-a na P2P. `routing: :peers` nie oznacza fizycznego P2P,
  a ping relay nie mierzy bezpośredniego połączenia. Regresje: `realtime_p2p_*`.
- Ctrl+F4 odróżnia pomiar HTTP, UDP do serwera pośredniczącego i RTT do
  poszczególnych uczestników P2P. Ścieżkę odczytuj z natywnego
  `Session#p2p_status`, nie z opcji stołu; po wygaśnięciu P2P nie odczytuj
  starego RTT jako bieżącego. Mieszane połączenia opisuj osobno. Odczyt
  nie wysyła dodatkowych sond ani nie uruchamia połączeń lub callbacków.
  Regresje: `ping_p2p_test.rb`, `ping_p2p_dictionary_test.rb`.
- Koordynowanie meczu przez gospodarza, także będącego obserwatorem, nie
  oznacza przekazywania przez niego każdej wiadomości. Dla akcji rozstrzyganych przez uprawnionego
  nadawcę wybieraj rozsyłanie przez relay bez dodatkowego skoku przez hosta.
  Model wymagający zatwierdzenia przez hosta musi mieć uzasadnienie i pomiar;
  nie przełączaj automatycznie wszystkich gier na `routing: :peers`.
- Nie czekaj na sieć ani dysk w klatce UI. Gotową akcję wysyłaj w tle od
  razu, bez czekania na okresowy pakiet lub następną klatkę. Zastępowalne
  pozycje mogą zachowywać tylko najnowszą wartość; ważnych akcji nie gub.
- Zachowuj uwierzytelnienie nadawcy, ID meczu/generacji, kolejność,
  deduplikację, ograniczone kolejki i pełne potwierdzenia wymaganych osób.
  Odbiorca chwilowo nieobecny nie znika z wymagań dostawy. Kolejna partia
  dostaje nowego klienta; stare zadania i powtórne zaproszenia nie mogą
  naruszać nowego połączenia. Odzyskiwanie ma działać bez Entera gracza.
- LiveSessions przechowuje trwały stan stołu i wyniki; nie uzależniaj
  każdego ruchu ani bezpiecznej lokalnej prezentacji od trwałego zapisu.
  Nie przyspieszaj kosztem uprawnień do punktów lub zgodności rozstrzygnięć.
- Mierz osobno HTTP, relay RTT, kolejki/UI, zastosowanie akcji i trwały
  zapis; nie odejmuj surowych zegarów różnych komputerów. Sprawdzaj ludzi
  i boty, różne miejsca, gospodarza-obserwatora, rewanż,
  utratę/duplikację/kolejność, tło i reconnect.
  Cztery kopie jednego komputera nie zastępują różnych łączy. Nie maskuj
  transportu zmianą fizyki ani nie uznawaj niewyjaśnionych zacięć za naprawione.

Uzasadnienie i pomiary: `docs/PONG_RELAY_DELIVERY_233.md`,
`docs/PONG_IMMEDIATE_DISPATCH_233.md`, `docs/PONG_RECEIVE_INVITATION_233.md`.

## Weryfikacja

Nowe wspólne funkcje stołu opisuje `docs/IMPLEMENTATION_AFTER_225.md`:

- Wariant/ustawienia Ctrl+R pochodzą z `table_options_announcement` i tych
  samych definicji co dokument ustawień. Nie utrzymuj drugiej listy reguł.
- Licznik S planszówki implementuje przez `remaining_piece_counts(replay)`
  w kolejności graczy; licz faktyczną planszę, nie wynik czy stan początkowy.
  Nie przypinaj literowych skrótów gry do edytowalnego czatu.
- Prywatność jest opcją wspólnego tworzenia stołu, nie ustawieniem każdej gry.
  Nie publikuj prywatnej aktywności. Ważność prywatnego powiadomienia musi
  pochodzić z serwerowego zaproszenia, nie z założonego terminu aplikacji.
- Zapis korzysta ze standardowego replaya i `saved_game_schema_version`.
  Nowa gra określa `save_game_error` dla niebezpiecznych faz albo wyłącza
  zapis przez `supports_saved_games?`. Jeśli wartości zdarzeń zawierają nazwy
  kontrolerów, implementuje `restored_event_value` dla tych konkretnych pól.
  Nie zastępuj graczy ani nie zamykaj stołu przed potwierdzonym zapisem archiwum na koncie.

- Uruchom celowane testy podczas pracy.
- Przed pull requestem uruchom `ruby tools/run-tests.rb`.
- Zmiana transportu wymaga testów `live_sessions_*`, `transport_test.rb`,
  `game_sync_test.rb` i scenariusza wielu klientów.
- Zmiana wspólnej powierzchni wymaga testu samej powierzchni oraz co najmniej
  jednej dotkniętej gry.
- Nie zmieniaj numeru wydania ani nie podpisuj paczki bez wyraźnego polecenia
  maintenera.

## Dane, których nie wolno dodawać

Nie zapisuj tokenów MCP, kluczy, certyfikatów, profili ELTEN-a, logów z danymi
prywatnymi, poświadczeń serwera ani podpisanych paczek `.eltsetup`.

## Zasoby dźwiękowe

Domyślny format dla każdego nowego efektu, głosu, pętli i muzyki:
Ogg Opus `.opus`, 144 kb/s VBR, 48 kHz, ramki 20 ms, libopus audio,
complexity 10. Zachowuj mono/stereo, metadane i poziomy; nie normalizuj,
nie przycinaj i nie przekodowuj wielokrotnie plików już zgodnych.
Używaj `tools/encode_audio.rb` oraz oryginału poza paczką. Samo przemianowanie
pliku nie jest konwersją. Pakowanie odrzuca inne formaty i fałszywy nagłówek
Opus, ale nie koduje ponownie; identyfikatory dźwięków pozostają bez rozszerzeń.
`tools/generate-pong-echo.rb` również produkuje Opus z deterministycznego PCM.
Szczegóły procedury: `docs/BUILDING.md`. Licencje i autorstwo zachowaj.

## Kontrakty po uzupełnieniu buildu 239

- Jedna instancja UI na proces: `GameRoomSingleInstance` przełącza natywny
  wątek, nie uruchamia `main` ponownie. Właścicielem nie jest sam widget.
  Odrzucone uruchomienie nie zamyka wspólnej puli dźwięków. Konkretne akcje
  czekają na granicę formularza, nie przerywają dialogów modalnych.
  ELTEN może pozostawić zakończony wątek przekierowanego uruchomienia na
  liście Okna. Usuwaj wyłącznie własne oznaczone i już zakończone wątki,
  na aktywnym UI po przełączeniu, także w formularzu modalnym. Nie zabijaj
  wątków i nie porządkuj cudzych okien. Sprawdzaj natywny cykl uruchomienia,
  nie tylko wartość zwróconą przez blokadę (`single_instance_native_test.rb`).
  Zimne wejście z widgetu (stół, tworzenie, preset, Ctrl+J) planuje nową
  scenę programu przez natywne `insert_scene`; nie otwieraj długotrwałego
  formularza wewnątrz callbacku Scene_Main ani na współdzielonym obiekcie
  widgetu. Core ma ustawić kontekst sceny i zakończyć jej cykl życia.
  Regresja: `widget_scene_navigation_test.rb` — także inne okno i powrót.
- `DiscoveredSession` jest związany z połączeniem, które odkryło stół.
  Wiersz przekazany przez widget lub powiadomienie nie może pożyczać tego
  połączenia nowemu oknu gry: dołączenie rozwiązuje identyfikator we własnym
  magazynie LiveSessions, którego callbacki obsługuje wykonawca partii.
  Po zmianie endpointu unieważniaj odkryte obiekty. Sprawdzaj publiczny
  i prywatny stół oraz ruch za innym oknem po zimnym wejściu z widgetu,
  nie tylko osobno nawigację i synchronizację. Regresja:
  `live_sessions_discovery_owner_test.rb`.
- Statystyki: callbacki UI/replay tylko odkładają kopie danych do ograniczonej
  pamięci; atomowy zapis i sieć należą do workera. Błąd telemetrii nie może
  przerwać gry. Nie ignorować konfliktów innych niż sama data powtórnego
  rozstrzygnięcia tej samej partii. Retencja usuwa tylko własne wygasłe
  raporty obecności, nigdy historyczne statystyki.
- Prezentacja planszy jest lokalna. Zapisuj wyłącznie jawnie dopuszczone
  flagi, a orientację względem miejsca gracza; nie zapisuj kursora i szkiców.
  Nowe stoły Chińczyka mają `enter_on_one: true`, stare zdarzenia bez tej
  opcji nadal wymagają dawnych zasad. Nie zmieniaj znaczenia starych rzutów.
- Ctrl+M i Ctrl+Shift+R dotyczą zaznaczonej osoby na liście uczestników,
  nie pola gry. Pomoc sprawdza bieżącą dostępność, a wywołanie ponownie
  weryfikuje uprawnienia i tożsamość, nie sam indeks wiersza.

## Czytelne kopie pytań quizu

- Po każdej zmianie pytań, odpowiedzi, podziału lub dodaniu zestawu uruchom
  `ruby tools/export-quiz-text.rb` i dołącz aktualne pliki `docs/quiz-questions/*.txt`.
- Pliki do czytania zawierają kolejny numer w osobnej linijce przed pytaniem
  (od 1 w każdym zestawie), treść, odpowiedzi A–D i wskazanie poprawnej
  odpowiedzi, **bez technicznych identyfikatorów pytań**. Nie edytuj ich ręcznie: źródłem
  prawdy są zestawy w `content/`. Pełny Wiedźmin i oba podzestawy muszą być zgodne.
- `ruby tools/export-quiz-text.rb --check` oraz `test/quiz_text_export_test.rb`
  wykrywają nieaktualne kopie. Przy nowym zestawie sprawdź także jego obecność
  w eksporcie. Nie dołączaj TXT ani narzędzia eksportu do instalatora gry.

## Pakowanie zawartości wykonawczej

Nigdy nie przekazuj całego repozytorium do rekursywnego pakowania ELTEN-a.
Najpierw przygotuj oddzielny katalog przez `tools/release_files.rb`.
Wspólna lista dopuszcza kod produkcyjny, dane gier, nagrania, gotowe MO,
manifesty oraz licencje i informacje o źródłach. Testy, narzędzia, docs,
AGENTS/README/CONTRIBUTING/CHANGELOG.md, źródłowe katalogi tłumaczeń,
raporty importu i materiały redakcyjne pozostają w repo, nie w instalatorze.
Zasady i changelog aplikacji są w przygotowanym kodzie/tłumaczeniach.
Nowy nietypowy zasób wykonawczy dodawaj jawnie do reguł pakowania wraz
z celowanym testem; nie naprawiaj brakującego pliku kopiowaniem całego repo.
Przed wydaniem sprawdzaj dokładny zbiór plików, zależności, wymagane dźwięki,
zgodność bajtów ze snapshotem, podpis i binarne wczytanie gier/treści/PL/EN.
Testy uruchamiaj z katalogu źródeł przeciw gotowej paczce. Brak testów
w paczce jest oczekiwany; brak produkcyjnego pliku nigdy nie może być
maskowany wczytaniem jego odpowiednika z dysku. Zachowaj ochronę krótkiej
ścieżki stagingu na Windows i nie wydawaj archiwum z samym manifestem.
