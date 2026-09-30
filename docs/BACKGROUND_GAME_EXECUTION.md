# Wykonanie partii i prezentacja za innym oknem

`GameRoomSessionRunner` wykonuje model, polityki automatyczne i boty bez
formularza. Widoczna i przykryta gra korzystają z tego samego wykonawcy.
`GameScreen` zachowuje kontrolki, obsługę klawiszy, mowę, dźwięki, fokus,
historię i dialogi. Za obcym oknem nie są aktualizowane kontrolki ani
wywoływana synteza z wątku roboczego. Odczyt i efekty już odebranych zdarzeń
obsługuje jednak aktywny wątek UI, także przed powrotem do gry. Po powrocie
ekran pokazuje potwierdzony replay, bez ponownego odczytywania tych zdarzeń.

Pong i Audio Ball nie korzystają z tego wykonawcy. Ich niezależna symulacja,
protokół pauzy, wejście i Communications pozostają bez zmian.

## Mowa i dźwięki podczas otwartych Wiadomości lub forum

Wykonawca publikuje skopiowany pakiet prezentacji po istniejącym
odczycie stanu; nie odpytuje serwera dodatkowo. `GameRoomBackgroundPresentation`
rejestruje aktywny ekran i korzysta z wąskiego mostu w `EltenAPI::UI#loop_update`.
Oryginalna metoda działa bez zmian; po niej tylko aktualny wątek UI może
przekazać gotowe zdarzenia przykrytej gry do istniejących prezenterów.
Nie jest to drugi `GameScreen#run`, globalny tick rozszerzeń ani ręczne
aktualizowanie formularza gry. Most nie czyta klawiatury i nie zmienia
aktywnego okna, fokusu, szkicu, zaznaczenia lub pozycji w historii.

Używane są te same opisy zdarzeń, przejścia tur, wynik, selektor dźwięków,
ustawienia głośności i wspólne kursory deduplikacji. Mowa ma `stop: false`
i `break_sequence: false`. Sekwencja dźwięków Statków jest kontynuowana
również bez kolejnego zdarzenia sieciowego. Ogłoszenia czasu quizu używają
tego samego zegara sesji i kluczy co widoczny ekran. Komunikaty czatu są
przekazywane tą samą ścieżką; formularz pozostaje nietknięty.

Rewanż może nadejść, gdy gracz nadal przebywa na forum. Kursor prezentacji
rozróżnia sesje, ale nie porównuje ich ID liczbowo: natywne identyfikatory
są losowe. Powrót starego widoku nie może cofnąć ogłoszonej już nowej partii.
Odgłosy wejścia/wyjścia również używają jednej projekcji uczestników, aby
stary bufor ekranu nie generował pozornego wyjścia i ponownego wejścia.

Most hosta nie przechowuje closure ze starej przestrzeni aplikacji. Jest
instalowany raz, a zarządzane rejestracje są usuwane po zamknięciu gry.
Bez aktywnej rejestracji niczego nie odczytuje ani nie odtwarza. Nie zmieniono
plików źródłowych ELTEN-a. Lokalne dialogi Krowy nadal otwiera jej widoczny
adapter, nie prezenter działający za innym oknem.

Regresje: `test/ui/game_background_presentation_test.rb` oraz
`test/ui/game_background_native_input_test.rb`. Pierwszy obejmuje pełną partię,
rewanż, losowe ID, odczyt wyniku, sekwencję audio, zegar quizu, deduplikację,
czyszczenie rejestracji i 20 binarnych przeładowań przestrzeni aplikacji.
Drugi używa natywnych kontrolek, klawiatury i adaptera mowy hosta z kontrolowanym
źródłem znaków: polski tekst, kursor i zaznaczenie nie ulegają zmianie.

## Granice bezpieczeństwa

- Subskrypcja `GameRoomSessionFeed` ma własne złączane sygnały. Odczyt przez
  wykonawcę nie zużywa sygnału przeznaczonego dla ekranu.
- Dostarczane są tylko gotowe callbacki własnego endpointu. Lokalny przebieg
  co 50 ms nie oznacza odpytywania serwera. Odczyt stanu następuje po zmianie,
  przy istniejącej weryfikacji zapisu lub odzyskiwaniu połączenia.
- Model wykonawcy i model planisty są oddzielone od modelu interfejsu.
  `ActionContext` zawiera skopiowane dane, nie kontrolki. Szkic Państw-miast
  pochodzi z UI i ma identyfikator własnej rundy/fazy.
- Zachowane są `Coordinator`, `Simulation`, `TurnController`, `action_for`
  i repozytorium. Nie dodano heurystyk, kar, wyborów odpowiedzi za człowieka
  ani innej autoryzacji. Seed oraz budżety wyszukiwania bota pozostały takie
  jak w dotychczasowej ścieżce.
- Planowanie bota nie trzyma blokady zapisu. Po obliczeniu decyzji wykonawca
  dostarcza callbacki odebrane podczas obliczeń, ponownie odczytuje stan
  i odrzuca nieaktualny plan. Przechwycenie UNO lub powiedzenie Makao nie
  musi czekać na zakończenie obliczeń bota.
- Zapis akcji, zmiana sesji i operacje sieciowe ekranu mają wspólną krótką
  granicę synchronizacji. Oczekiwanie na nią odbywa się w `Tasks`, nie przez
  zablokowanie pętli UI. Nie obejmuje oczekiwania na formularz ani planisty.
- Kilka otwartych instancji tego samego konta/stołu wybiera jednego
  wykonawcę. Pierwszeństwo ma aktywne okno, a gdy wszystkie są przykryte —
  ostatnie. Przekazanie wykonania uzgadnia stan i nie omija przerwy po
  niepewnym zapisie. Ten mechanizm nie przekazuje gospodarza serwera.
- Zwykły wybór jest związany z wyświetloną rewizją. Gry z równoległym
  wejściem dopuszczają tylko jawnie opisane wyjątki we własnej rundzie/fazie:
  odpowiedzi quizu i Państw-miast, floty Statków, próby wyścigu Krowy,
  przechwytywanie/deklaracje UNO oraz deklaracja Makao. Ostatecznie zawsze
  waliduje je `action_for` na świeżym stanie. Zachowano również karę UNO
  za spóźnioną próbę; stara karta nie przechodzi do kolejnego rozdania.
- Zamrożenie zapisu, przerwanie partii i zamknięcie stołu zatrzymują akcje.
  Rewanż używa nowego ID sesji. Niepewny zapis zachowuje istniejącą ścieżkę
  potwierdzenia, identyfikator wiadomości i backoff; nie jest wysyłany jako
  nowy ruch. Zamknięcie nie zabija wątku w połowie zapisu.
- Przejściowy błąd zapisu akcji automatycznej podlega backoffowi, również
  dla lokalnego szkicu. Błąd programu zatrzymuje ponawianie wadliwej akcji. Błąd trafia do adaptera UI dopiero
  z jego własnego wątku. Powrót po zakończonym odzyskiwaniu połączenia nie
  rozpoczyna od nowa historycznej 30-sekundowej przerwy.

## Wskazówki dla nowych gier

Model i polityki automatyczne muszą działać bez UI. Nie wolno w nich otwierać
formularzy, odczytywać aktywnej kontrolki, wołać `loop_update` lub mówić.
Niestandardowe argumenty konstruktora trzeba zachować w `build_session_game`
(przykład: bank słów Krowy). Planista ma własną, trwałą instancję modelu;
nie należy współdzielić jej mutowalnych cache z ekranem.

Termin opisuje `automatic_action_due?`, a legalną operację
`automatic_action`/`action_for`. Nie zakładać, że cała polityka będzie
wywoływana bez końca dla niezmienionej pozycji. Jeżeli potrzebny jest szkic,
zdefiniować `automatic_surface_identity` i bezpieczny snapshot danych.
`concurrent_session_input?` nie może być ogólnym pominięciem kontroli
rewizji; porównuje konkretną tożsamość rundy i rodzaju operacji.

Lokalne usługi prezentacyjne Krowy (dialog definicji, galeria, propozycja
publikacji wyniku i prywatne pokazanie rozwiązania po poddaniu) nadal należą
do adaptera UI. Wykonawca obsługuje stan, ocenę prób i publiczne rozstrzygnięcie,
nie przenosi dowolnej metody `game_client` do wątku roboczego.

## Weryfikacja

Testy wykonawcy są w `test/session/`, a prezentacji w
`test/ui/game_background_presentation_test.rb` i
`test/ui/game_background_native_input_test.rb`. Sprawdzaj wiele instancji,
planowanie poza blokadą, niepewny zapis, powrót, deadline, rewanż i zamknięcie.
Próba żywego klienta musi potwierdzić wyjście mowy i aktywne audio jeszcze
za natywnym oknem. Zgodny model po powrocie nie dowodzi prezentacji w tle;
atrapy audio nie zastępują odsłuchu.
