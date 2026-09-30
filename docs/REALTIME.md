# Gry czasu rzeczywistego

Pong i Audio Ball mają własny lifecycle klienta (`session_runner? false`).
`Channel` i `EventChannel` współdzielą połączenie Communications, kolejki,
ping i dostawę. Klient gry odpowiada za fizykę, reset własnych pól i legalność
przejść. LiveSessions przechowuje stół, rozpoczęcie i trwałe rozstrzygnięcia.

## Droga akcji i uprawnienia

1. Aktywne pole gry przyjmuje świeże wejście; silnik sprawdza przejście.
2. Zaakceptowana akcja trafia od razu do ograniczonej kolejki wysyłki w tle.
3. Communications rozsyła ją do uczestników bez dodatkowego skoku przez
   gospodarza, gdy rozstrzygnięcie należy do nadawcy.
4. Odbiorca sprawdza autentycznego nadawcę, miejsce, mecz, generację,
   kolejność i duplikaty przed zastosowaniem i prezentacją.
5. Gospodarz uzgadnia punkt ze wszystkimi wymaganymi ludźmi. Dopiero zgodne
   potwierdzenia pozwalają na zdarzenie prezentacji punktu. Wynik i koniec
   partii zatwierdza normalna ścieżka `action_for`, repozytorium i replay.

W Pongu człowiek rozstrzyga własny serw, odbicie i chybienie. Gospodarz
prowadzi boty, także jako obserwator; nie przejmuje paletek ludzi.
Zastępowalne pozycje i snapshoty mają osobną ścieżkę koordynacji przez
gospodarza. Zdalny obserwator odtwarza pełny snapshot po sprawdzeniu nadawcy
i epoki; nie odtwarza od zera nieotrzymanej historii odbić.
[Audio Ball](AUDIO_BALL.md) opisuje własne przejścia i uprawnienie odbiorcy
lotu do rozstrzygnięcia obrony.

Ważne akcje wymagają pełnego potwierdzenia dostawy. Chwilowo nieobecny odbiorca
nie znika z wymagań. Pozycje mogą zachowywać tylko najnowszą wartość; akcje
nie mogą ginąć przy złączeniu pakietów. Oczekiwanie na sieć lub dysk nie należy
do klatki UI. Nowa partia tworzy nowego klienta; stare zadania, zamknięcia
kanału i powtórne zaproszenia nie mogą naruszyć nowego połączenia. Reconnect
przywraca rejestrację pingu i ustawienia kanału, bez wymaganego Entera.

## Pauzy, timery i prezentacja

Timer korzysta z natywnego lifecycle `FormTimer`, z bramką kadencji meczu
opisaną w [HOST_API.md](HOST_API.md). Nie nadrabia zaległych klatek.
Gotowa ważna akcja nie czeka na następny okresowy pakiet ani klatkę.

Zapowiedź pary serwisowej Ponga jest zwykłą mową. Koniec syntezy nie jest
barierą gotowości. Po punkcie obowiązuje harmonogram wyniku i zwykłe 2,7 s
przygotowania; późna zapowiedź nie rozpoczyna kolejnego odliczania.
Gotowość sieciowa nadal jest wymagana. Weryfikacja obejmuje syntezator, który
nigdy nie zwraca końcowego indeksu, oraz przerwanie mowy.

Zgodna prezentacja punktu może wyprzedzać trwały zapis. Nie może sama zmieniać
wyniku ani powtarzać efektu po późniejszym zapisie. Pauza połączenia zatrzymuje
zegar gry; odtwarzanie stanu nie uznaje niepotwierdzonej wymiany za punkt.
Pomoc i ustawienia respektują blokadę wejścia oraz obsługę puszczenia klawiszy.

## P2P i pomiary

Opcjonalne pełne P2P używa natywnego `p2p: :full` oraz
`p2p_participants_limit`. Domyślnie jest wyłączone; limit to 8 uczestników,
0 oznacza brak limitu. Obserwatorzy wliczają się do limitu, miejsca botów nie.
Brak połączenia bezpośredniego pozostawia relay. Game Room nie zmienia
globalnej zgody ELTEN-a na P2P. `routing: :peers` określa odbiorców,
nie dowodzi fizycznego połączenia bezpośredniego.

Ctrl+F4 rozdziela HTTP, UDP do relay i RTT poszczególnych uczestników P2P.
Stan ścieżki pochodzi z `Session#p2p_status`, nie z opcji stołu. Wygasłe RTT
nie jest bieżącym pomiarem; połączenia mieszane wymagają osobnego opisu.
Odczyt nie wysyła sond ani nie uruchamia połączeń lub callbacków.

Mierz osobno HTTP, relay RTT, kolejki/UI, zastosowanie akcji i trwały zapis.
Nie odejmuj surowych zegarów różnych komputerów. Scenariusze powinny obejmować
ludzi, boty, gospodarza-obserwatora, zastępstwa, rewanż, tło, reconnect oraz
utratę, duplikację i zmianę kolejności. Cztery procesy na jednym komputerze
nie zastępują różnych łączy. Regresje są w `test/realtime/`,
`test/games/axel_pong/` i `test/games/audio_ball/`.
