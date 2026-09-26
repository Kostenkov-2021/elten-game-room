# Architektura

## Przepływ danych

ELTEN uruchamia `EltenGameRoom` z pliku `__app.rb`. Program tworzy repozytoria
stołów i partii nad jednym magazynem LiveSessions. Stół jest sesją publiczną
albo prywatną, a jej stos jest autorytatywną, uporządkowaną historią pokoju,
czatu, rozpoczętych partii i ruchów.
Stan partii nie jest przechowywany jako jeden mutowany obiekt. Serwer zawiera
uporządkowane zdarzenia, a klasa danej gry odtwarza z nich `Replay`.

Typowy ruch przechodzi następującą drogę:

1. wspólna powierzchnia gry tworzy opis akcji;
2. gra waliduje akcję w `action_for` i zwraca `ActionPlan`;
3. `GameRepository` dopisuje cały plan ruchu jako jeden atomowy wpis stosu;
4. LiveSessions dostarcza ten sam wpis pozostałym uczestnikom;
5. każdy klient odtwarza stan i aktualizuje formularz dopiero po rzeczywistej
   zmianie.

To rozdzielenie jest ważne: interfejs nie ustala zasad, a transport nie
interpretuje ruchów.

## Warstwy

### Manifest i składanie programu

`__app.rb` zawiera metadane ELTEN-a, deklaracje tabel pomocniczych,
rejestr gier i główną klasę programu. Bieżące tabele służą rejestracji
użytkowników, ogłoszeniom globalnego lobby, subskrypcjom stołów oraz funkcjom
Krowy. Dawne tabele stołów, członkostwa, zaproszeń i ruchów nie są drugim
backendem gry. Archiwa konta przechowuje usługa prywatnych plików, nie tabela.

### Dostęp do tabel pomocniczych

Każde wywołanie `program_main` oraz wejście przez powiadomienie ponownie
sprawdza dostęp do `game_room_users` minimalnym odczytem dla bieżącego konta.
`GameRoomServerTables` współdzieli wynik z istniejącymi uchwytami tabel.
Detekcja korzysta z odpowiedzi serwera: kod
`apps.tables.stamp_required` oznacza tryb deweloperski bez tabel.

Po odmowie nie są wykonywane dalsze odczyty ani zapisy tabel pomocniczych.
Nie uruchamia się odpytywanie globalnej historii lobby; funkcje wymagające
tabel wskazują ograniczenie dostępu. Lokalne kategorie Ustawień nadal działają,
a nieznanych subskrypcji nie wolno zapisać jako pustej listy. Discovery,
rozgrywka, zaproszenia oraz historia i czat pokoju korzystają z LiveSessions
i powiadomień ELTEN-a, nie z dawnej tabeli zaproszeń.
Timeout i inne błędy również wstrzymują operacje tabelowe do kolejnego wejścia,
ale są przedstawiane jako problem sprawdzenia dostępu, nie tryb deweloperski.
Ponowne uruchomienie maina może przywrócić funkcje tabelowe bez tworzenia
nowej instancji aplikacji.

### Modele gier

`GameRoomGames::Base` definiuje wspólną umowę: identyfikator, nazwę, zasady,
liczbę graczy, opcje, walidację, start partii, replay, akcje, powierzchnię,
historię i opcjonalną strategię bota. `TurnBasedBoardGame` dodaje standardowy
model ruchu figura–pole dla planszowych gier turowych.

Każda gra musi deterministycznie odtworzyć ten sam stan z tych samych zdarzeń.
Losowość powinna być reprezentowana przez zdarzenie lub kontrolowane źródło z
`game_random.rb`.

### Wspólny interfejs

`GameScreen`, `GameRoomLayout`, `GameRoomShortcuts` i `GameSurfaces` budują
dostępny formularz partii. Powierzchnie obejmują między innymi planszę z
figurami, tor pionków, rękę kart, tacę kości, panel poleceń, arkusz odpowiedzi i
widok oceniania.

Formularz stołu i partii ma wspólną kolejność: rozpoczęcie, restart albo
informacja o oczekiwaniu, opcjonalna powierzchnia gry, czat, historia i
użytkownicy. Rozpoczęcie jest dostępne przed pierwszą partią, a restart po jej
zakończeniu, oba tylko dla właściciela. Pozostali uczestnicy widzą w tym samym
miejscu nieaktywną informację o oczekiwaniu. Nową sesję tworzy standardowe
repozytorium, a kontroler stołu otwiera jej ekran.
Wejście do własnego oczekującego stołu ustawia fokus na rozpoczęciu gry, a u
pozostałych osób na informacji o oczekiwaniu. Start, restart i koniec partii
nie wyrywają fokusu z czatu, historii lub listy osób: zachowują również szkic,
zaznaczenie i oglądany wpis. Zmiana powierzchni gry jest wykonywana cicho,
bez przerywania końcowych komunikatów. Nie ma osobnego trybu podglądu. Próby
wykonania akcji nadal przechodzą przez `action_for`, które
odrzuca je z komunikatem zakończonej gry. Zwykłe aktualizacje tej samej partii zachowują
aktywną sekcję, tożsamość zaznaczonej osoby, szkic i zaznaczenie czatu oraz
przeglądaną pozycję historii.

`GameRoomLayout::Screen` zachowuje formularz, listy, przyciski i edytor czatu;
zmienia jedynie potrzebną powierzchnię gry. Identyfikator sesji pozwala zachować
zaznaczenie planszy po ponownym wejściu i wyczyścić je dla nowej partii.
Powiązania zdarzeń są wymieniane
bez mnożenia natywnych handlerów, a timery usuwane przy opuszczeniu widoku.
`GameRoomParticipantMenu` wiąże jedno menu kontekstowe wspólnego formularza:
zasady gry przez Ctrl+F1, zapraszanie użytkownika online przez Ctrl+I,
zapraszanie z kontaktów przez Ctrl+Shift+I oraz dodawanie komputera przez
Ctrl+O. Menu i skróty działają z każdego pola stołu, także podczas partii i po
jej zakończeniu. Delete pozostaje lokalną akcją listy użytkowników i usuwa
wyłącznie wskazany komputer. Wszystkie operacje sprawdzają aktualny stan i
uprawnienia także po otwarciu menu. Powrót z zasad zachowuje wcześniejszy fokus
i szkic czatu.

Przyjmowanie i odrzucanie zaproszeń jest dostępne w menu kontekstowym listy
menu głównego, przez Ctrl+J i Ctrl+Shift+J. Pozycja „Zaproszenia” nadal otwiera
standardową ścieżkę przyjmowania. Powiadomienie pozwala przyjąć lub odrzucić
konkretne zaproszenie, z weryfikacją jego aktualności i usunięciem powiadomienia
po obsłużeniu. Formularze nie przechwytują globalnie skrótów zaproszeń;
nie są one dostępne z planszy, czatu ani historii.

`RoomPresentation` przechowuje identyfikator uczestnika oddzielnie od etykiety.
Gra udostępnia `participant_scores(replay)`: mapę uczestników na punkty albo
`nil`, jeśli nie prowadzi punktacji. Farkle, Tysiąc, Spades i Państwa-miasta
zwracają wyniki z odtworzonego stanu. Spades przypisuje wynik drużyny jej
członkom. Zero jest wynikiem; obserwator ani gra bez punktacji nie dostają
sztucznej etykiety punktów. Wyniki zakończonej partii pozostają przy obecnych
uczestnikach do rozpoczęcia kolejnej.

Gra opisuje powierzchnię i akcje. Nie powinna bez potrzeby tworzyć własnego
formularza, przechwytywać systemowych klawiszy ani ręcznie sterować pętlą UI.

### Stoły, uczestnicy i cykl partii

`game_room_screens.rb`, `game_lifecycle.rb`, `game_participants.rb` oraz
repozytoria lobby i aktywności obsługują tworzenie stołu, dołączanie, boty,
rozpoczęcie, zakończenie i następną partię.

Bot ma trwały identyfikator i losowaną nazwę. Usuwa się wybranego bota,
nie ostatnią pozycję numerowanej listy. Skład drużyn odwołuje się do obecnych
uczestników. Uprawnienia, fazę i obecność osoby sprawdza się ponownie przy
zatwierdzeniu. Ctrl+M przekazuje gospodarza; Ctrl+Shift+R na liście osób
zastępuje wskazanego gracza/bota obecnym niegrającym człowiekiem albo nowym
botem, jeśli gra to dopuszcza. To nie zamiana dwóch grających osób.

Skład rozpoczętej partii jest utrwalany w zdarzeniu `game_started` na stosie
sesji. Późniejsze zastępstwa mają własną historię i epokę; odtwarzanie mapuje
akcje według obsady z chwili ich wykonania. Powrót człowieka nie odbiera
botowi miejsca automatycznie. Samo przykrycie okna nie oznacza odejścia.

### Transport

`GameRoomLiveSessionStore` używa natywnego API ELTEN-a 3.0.4. Publiczne
wyszukiwanie sesji zastępuje tabelę stołów, bezpośrednie dołączenie do odkrytej
sesji zastępuje bootstrap przez Signals, a natywne zaproszenia zastępują własne
tabele zaproszeń. Zmiany pokoju, czat, start partii i ruchy trafiają do jednego
stosu i mają wspólną kolejność. Zamknięcie sesji usuwa stół z listy bez osobnego
sprzątania rekordu.

Widoczna historia nadal jest dzielona na `Wszystko`, `Gra`, `Czat` i
`Zdarzenia pokoju`. Podział jest wyłącznie filtrem prezentacji nad jednym
chronologicznym strumieniem i nie rozdziela ponownie danych na osobne magazyny.

`GameRoomSync::Controller` zbiera powiadomienia i uruchamia kontrolowane
odzyskanie stanu po błędzie lub luce. Nie należy zastępować tego częstym,
okresowym odpytywaniem serwera.

Axel Pong i Audio Ball mają wspólną, domyślnie wyłączoną opcję pełnego P2P.
Po jej zaznaczeniu formularz pokazuje następne pole: limit uczestników,
domyślnie 8; 0 oznacza brak limitu. `realtime/p2p_options.rb` definiuje opcje
i ich walidację, a `Channel` przekazuje do natywnego `create_session`
`p2p: :full` oraz `p2p_participants_limit`. Wyłączenie pozostawia dotychczasowe
argumenty tworzenia sesji. Ustawienia pochodzą z opcji stołu, także przy
ponownym połączeniu i po zmianie gospodarza; nie są lokalną preferencją gracza.

Limit obejmuje natywnych uczestników Communications, w tym obserwatorów,
ale nie osobne miejsca botów. ELTEN zestawia połączenia bezpośrednie zgodnie
z ustawieniami prywatności klienta i dostępnością sieci; brak ścieżki P2P
lub przekroczenie limitu pozostawia transport przez relay. Game Room nie
zmienia globalnej zgody na P2P ani uprawnień nadawców. Pełne P2P obejmuje
obie ścieżki Communications (pozycje i potwierdzane akcje), nie przenosi
czatu, członkostwa ani trwałego zapisu punktów poza LiveSessions. Odczyt
pingu relay nadal dotyczy serwera, nie opóźnienia między graczami.
Lokalne regresje `realtime_p2p_*` nie zastępują próby na różnych łączach/NAT.

`GameRoomSessionRunner` jest jednym wykonawcą zwykłej partii w widocznym
i przykrytym oknie. `GameRoomExecutionPolicy` współdzieli czyste decyzje
o zastępstwie i przygotowanie planu bota z osobną ścieżką realtime; nie scala
ich pętli. Planowanie nadal odbywa się poza blokadą zapisu, a zatwierdzenie
ponownie sprawdza sesję, rewizję, gospodarza i epokę kontroli.

Most pracy w tle przekazuje dane do prezenterów na aktywnym wątku UI, nigdy
nie odczytuje klawiatury z workera. `GameRoomPresentationReplay` przechowuje
odizolowaną kopię ostatniego prefiksu: zachowuje wszystkie przejścia przed/po,
ale nie odtwarza drugi raz już gotowego stanu końcowego. Zmiana sesji, epoki,
opcji albo prefiksu wymusza pełną rekonstrukcję. `nil` stanu planszówki jest
poprawną wartością, nie błędem. Błąd programistyczny zatrzymuje wykonawcę
i trafia do UI/logu; nie udaje przejściowego rozłączenia i nie ponawia ruchów.

Format i walidację zapisu opisuje `saved_game_archive.rb`. `AccountSavedGames`
korzysta wyłącznie z prywatnych plików konta i potwierdza zapis przed
zamknięciem stołu. Historyczny adapter lokalny jest oddzielny, bez automatycznego
fallbacku. Ochrona niepewnego zapisu, czasu gry i sekretów nadal obowiązuje.

### Boty

`game_bots.rb` definiuje wspólną rejestrację i uruchamianie strategii.
Planowanie nie zapisuje ruchu bezpośrednio: wybiera legalną akcję, która
przechodzi przez tę samą walidację gry i repozytorium co akcja człowieka.
Specjalizowane strategie znajdują się w plikach `*_strategy.rb`; wspólny
przeszukiwacz drzewa w `game_tree_search.rb`.

Trening, arena, kampanie, eksperymentalne MCTS i narzędziowe modele punktacji
znajdują się w `tools/training/`. Nie są ładowane przez aplikację. Produkcyjne
polityki, wytrenowane profile i środowisko symulacji pozostają w `lib/`.

### Treści i języki

`game_content.rb` oraz `content/languages.rb` obsługują wersjonowane pakiety
treści i warianty językowe. Komunikaty interfejsu korzystają z funkcji `_()` i
są dostarczane w `locale/PL.mo`.

## Niezmienniki, których trzeba pilnować

- stos LiveSessions jest źródłem prawdy dla pokoju i partii;
- każdy ruch jest ponownie walidowany przy odtwarzaniu;
- klient nie zapisuje uczestnika przed potwierdzeniem LiveSessions;
- formularz odświeża się tylko po rzeczywistej zmianie stanu;
- bot nie omija reguł ani ścieżki zapisu człowieka;
- zmiana wspólnego szkieletu wymaga testu co najmniej jednej gry z każdej
  dotkniętej rodziny.
