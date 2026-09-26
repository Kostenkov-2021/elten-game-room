# Game Room 2.0.4 — build 239

## Polski

- Nowa wersja wymaga ELTEN-a 3.0.4 lub nowszego.
- Dodano Wojnę i Wojnę naukową autorstwa balteama, dla dwóch do ośmiu graczy, z możliwością gry z botami. W Wojnie porównuje się karty z zakrytej talii, a w Wojnie naukowej samemu wybiera się karty i korzysta z ich specjalnych właściwości.
- Dodano statystyki autorstwa balteama: odwiedziny, rozpoczęte i ukończone partie, z podziałem na gry i okresy. Otworzysz je przez Statystyki w menu głównym. Ctrl+W na liście opcji tego menu odczytuje bieżącą liczbę stołów publicznych i prywatnych oraz członkostw ludzi, wliczając obserwatorów, ale nie boty. Tryb deweloperski nie zbiera nowych statystyk.
- W deblowym Axel Pongu w trybie Arcade gracze jednej drużyny korzystają ze wspólnej tarczy. Zmianę zaproponował balteam.
- W ustawieniach stołów Axel Ponga i Audio Balla można włączyć bezpośrednie połączenia P2P. Opcja jest domyślnie wyłączona; po jej zaznaczeniu można ustawić limit uczestników P2P, domyślnie 8. Gdy bezpośrednie połączenie jest niedostępne, gra korzysta z serwera pośredniczącego.
- Ctrl+F4 rozróżnia teraz ping HTTP, połączenie Communications przez serwer pośredniczący oraz P2P. Przy połączeniach mieszanych podaje informacje osobno.
- Poprawiono wykrywanie szybkich naciśnięć i przytrzymywania klawiszy w Audio Ballu.
- Zaproszenia można przyjmować skrótem Ctrl+J oraz z menu kontekstowego w całym Game Roomie, również podczas gry, pisania na czacie, przeglądania historii i w ustawieniach.
- Ponowne uruchomienie Game Roomu przenosi do już otwartego okna, zachowując partię i szkic wiadomości. Poprawiono pozostawianie nieaktywnych wpisów w menu „Okna” ELTEN-a.
- Poprawiono otwieranie Wiadomości i innych okien ELTEN-a po wejściu do Game Roomu przez widget oraz odbieranie aktualizacji partii uruchomionej tą drogą.
- W Chińczyku jedynka domyślnie pozwala wyjść z bazy, lecz nie daje kolejnego rzutu. Zasadę można wyłączyć przy tworzeniu stołu. Skrócono opisy pozycji; Ctrl+C przełącza nazwy graczy i kolory, a C odczytuje ich przypisanie.
- Ustawienia prezentacji planszy w Szachach, Warcabach i Chińczyku są zapamiętywane lokalnie dla kolejnych stołów, bez zmiany preferencji innych graczy.
- Dodano 22 polskie imiona botów.
- Poprawiono wiele pytań quizowych, usuwając niejasne sformułowania i błędy językowe oraz doprecyzowując treść pytań i odpowiedzi.
- Dodano grę karcianą 3-5-8 autorstwa Guliwer777. Trzech graczy rywalizuje o lewy, wybiera kontrakty i wymienia karty między rozdaniami. Dostępna jest również gra z botami.
- Dodano czeskie i hiszpańskie tłumaczenie interfejsu autorstwa balteama. Język można wybrać w Ustawieniach, w kategorii Ogólne. Tłumaczenia nie obejmują zasad gier. Angielska nazwa Tysiąca to teraz „1000 card game”.
- Gospodarz może przekazać prowadzenie stołu innej osobie skrótem Ctrl+M. Jego wyjście nie zamyka już automatycznie całego stołu — prowadzenie przejmuje kolejny uczestnik, wraz z obsługą botów.
- Dodano zastępowanie uczestników podczas partii. Na liście osób wybierz gracza lub bota i naciśnij Ctrl+Shift+R. Możesz przekazać jego miejsce obecnemu obserwatorowi albo zastąpić człowieka nowym botem, jeśli gra obsługuje boty. Zachowane zostają ręka, wynik i miejsce w drużynie, a zastąpiony człowiek może dalej obserwować.
- W grach obsługujących boty wychodzący gracz jest automatycznie zastępowany komputerem. Po powrocie dołącza jako obserwator; gospodarz może ponownie przekazać mu miejsce.
- Zapisane partie są przechowywane na koncie, a nie tylko na danym komputerze. Można więc wznowić je po zalogowaniu się na innym urządzeniu.
- W Ustawieniach, w kategorii Ogólne, można wybrać, czy poza oknem stołu mają być odczytywane komunikaty oraz odtwarzany sygnał własnej tury. Te same ustawienia obowiązują podczas korzystania z innych okien ELTEN-a i po przełączeniu do innego programu.
- Listy stołów i widget pokazują dokładniejszą obsadę oraz informację, czy stół oczekuje na graczy, czy trwa już partia.
- Naprawiono tworzenie ofert wymiany w Monopoly. Gra nie powinna już zatrzymywać się na informacji, że gracz przygotowuje ofertę.
- Poprawiono powroty do stołu oraz odświeżanie uczestników, rąk i tur po zastąpieniu gracza lub zmianie gospodarza.
- Naprawiono okna korekty karty i powtarzania tury w Taboo. W Krowie usunięte słowa nie wracają już samoczynnie po przelosowaniu, a synchronizacja Dziennej Krowy obejmuje również dłuższą historię.
- Brak dostępu do tabel serwerowych nie blokuje już całego okna Ustawień. Ustawienia niewymagające tego dostępu pozostają dostępne.
- Ograniczono zbędne obliczenia przy odświeżaniu partii i podejmowaniu decyzji przez boty oraz gromadzenie niepotrzebnych danych po opuszczonych stołach.

## English

- This version requires ELTEN 3.0.4 or later.
- Added War and Scientific War by balteam, for two to eight players, with bots. War compares cards from a face-down deck; Scientific War lets you choose your cards and use their special powers.
- Added statistics by balteam: visits, started and completed games, with game and period filters. Open Statistics in the main menu. Ctrl+W on that menu's options list reads current public and private table counts and human memberships, including observers but not bots. Developer mode does not collect new statistics.
- In doubles Arcade Axel Pong, teammates now share their shield, as proposed by balteam.
- Direct P2P connections can now be enabled in Axel Pong and Audio Ball table settings. The option is off by default; enabling it reveals a P2P participant limit, defaulting to 8. If a direct connection is unavailable, the game uses the relay server.
- Ctrl+F4 now distinguishes HTTP ping, Communications through the relay server, and P2P. Mixed connections are reported separately.
- Improved detection of quick presses and held keys in Audio Ball.
- Invitations can be accepted with Ctrl+J or from the context menu throughout Game Room, including while playing, typing in chat, browsing history and using settings.
- Opening Game Room again returns to the already open window, preserving your game and message draft. Fixed inactive entries being left in ELTEN's Windows menu.
- Fixed opening Messages and other ELTEN windows after entering Game Room through the widget, and receiving updates for games opened this way.
- In Ludo, a 1 also allows leaving the base by default, but does not grant another roll. You can turn this rule off when creating a table. Position descriptions are shorter; Ctrl+C switches between player names and colours, and C reads their colour assignments.
- Board presentation choices in Chess, Checkers and Ludo are now remembered locally for future tables, without changing other players' preferences.
- Added 22 Polish bot names.
- Corrected many quiz questions, removing ambiguous wording and language errors and clarifying questions and answers.
- Added 3-5-8 by Guliwer777: a card game for three players, with trick-taking, contract selection and card exchanges between deals. You can also play against bots.
- Added Czech and Spanish interface translations by balteam. Choose the language in Settings > General. These translations do not include game rules. Tysiac is now called 1000 card game in English.
- The table master can transfer ownership to another person with Ctrl+M. Leaving no longer automatically closes the whole table: another participant takes over, including control of the bots.
- Participants can be replaced during a game. Select a player or bot in the Users list and press Ctrl+Shift+R. You can give their seat to a present observer or replace a person with a new bot if the game supports bots. The hand, score and team position are preserved, and the replaced person can keep watching.
- In games that support bots, a player who leaves is automatically replaced by a bot. They return as an observer, and the table master can give them a seat again.
- Saved games are stored on your account, not only on the computer where you saved them. You can resume them after signing in on another device.
- In Settings > General, choose whether game announcements and the sound for your turn are heard outside the table window. The same settings apply in other ELTEN windows and when you switch to another program.
- Table lists and the widget show more accurate participant counts and whether a table is waiting for players or a game is already in progress.
- Fixed creating trade offers in Monopoly. The game should no longer get stuck after announcing that a player is preparing an offer.
- Improved rejoining tables and updating participants, hands and turns after replacing a player or changing the table master.
- Fixed the card-correction and turn-replay dialogs in Taboo. In Krowa, deleted words no longer reappear after drawing another word, and Daily Krowa synchronisation now includes longer histories.
- Lack of access to server tables no longer blocks the entire Settings window. Settings that do not need that access remain available.
- Reduced unnecessary calculations when updating games and planning bot moves, and limited the retention of unneeded data from tables you have left.
