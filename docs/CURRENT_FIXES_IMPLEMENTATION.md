# Wdrożenie bieżącego planu — implementacja i próby MCP

Zakres: siedem punktów `CURRENT_FIXES_PLAN.md`, zatwierdzone 27 września 2026.
Bez nowej paczki, podpisu, zmiany wersji i publikacji. Każdy punkt wymaga
osobno testów celowanych oraz prób na rzeczywistych kontach. Nie uznawać
samego wyniku lokalnego za ukończenie punktu.

## Aktualny stan — 28 września 2026, po zakończeniu prób MCP

Siedem punktów jest w źródłach. Poniższe starsze sekcje opisują chronologię,
nie listę nadal niewdrożonych zmian. Nie zbudowano ani nie opublikowano paczki.

- **Bezczynność i obsada:** publikacja ostatniej aktywności, filtr 45 minut
  i Ctrl+W sprawdzone lokalnie oraz na własnych rzeczywistych stołach. Żywe
  próby ujawniły dwa kontrakty hosta: natywny stan odkrytej sesji to `open`,
  a wygasły uchwyt discovery może wymagać jednego ponownego odkrycia tego
  samego publicznego ID. Obie poprawki mają odrębne regresje; nie dołączamy
  do stołu w celu odczytania obsady. Sprawdzono także porzucanie późnego
  wyniku Ctrl+W po zmianie zaznaczenia/fokusu.
- **Chińczyk:** na rzeczywistej partii z botem sprawdzono oba sposoby
  prezentacji podczas ruchów, zbicia i końcowego wyniku. Partia zakończyła
  się po 263 rekordach. Przełączenie zachowuje źródłową historię; lokalny
  odczyt korzysta z historycznego miejsca, nie aktualnej nazwy zastępstwa.
- **Wolna sieć:** scenariusze obejmowały wszystkie 32 zarejestrowane gry,
  różne rodziny kontrolek, zapisy opóźnione o 1/3/10 s, ponowiony Enter,
  szkic i fokus czatu, błędy przed zapisem, niepewne potwierdzenie,
  anulowanie i dalszą grę. Nie w każdej grze sprawdzono każdą awarię ani
  pełną partię. Brak ponowienia całego lokalnego runnera.
- **Realtime:** single, debel czterech ludzi, dwóch ludzi i dwóch botów,
  trzech ludzi i bota; zmiany serwujących, nowy mecz na tym samym stole,
  ponowne połączenie kanału, zapis punktu +3 s, ruch podczas oczekiwania,
  menu osoby i czat bez przypadkowego serwu. W Audio Ballu sprawdzono
  wszystkie poziomy, trzy tory oraz gospodarza-obserwatora. Symulowane
  opóźnienie odbioru 200 ms jest opóźnieniem testowej kolejki, nie pomiarem
  rzeczywistego pingu. Niezależne łącza i NAT/P2P nie były testowane.
- **Cykl życia:** żywa próba 99 obejmuje zastąpienie człowieka podczas
  jego opóźnionego zapisu, powrót z powiadomienia jako obserwator,
  zastąpienie bota, zmianę gospodarza podczas czatu, wyjście gospodarza
  i dalsze ruchy botów. W Scrabble sprawdzono odejście i powrót bez botów.
  Ponowne uruchomienie aplikacji podczas oczekiwania zachowało jedną
  instancję. Ruchy Warcabów dochodziły pod otwartym Forum i Wiadomościami,
  przed powrotem do Game Roomu; późniejsze ruchy na obu kontach były zgodne.
- **Warcaby:** jedna poprawna geometria 8/10/12, bez gałęzi dawnych zapisów.
  Lokalnie 3512 porównań geometrii i replay oraz 385 przejść strategii;
  żywe otwarcia obu stron dla trzech rozmiarów, bicie, bot, obserwator,
  notacja i obrót. Nie zmieniano reguł bicia lub strategii bota.
- **Dźwięk up:** dokładne cięcie 3 s i format pozostają jak niżej.
  Sprawdzono natywne odtwarzanie/pętlę oraz użycie w partiach. To dowód
  działania odtwarzacza, nie subiektywna ocena odsłuchu; Audiodisc bez zmian.
- **Menu osoby:** rzeczywiste menu ELTEN-a w poczekalni, w trakcie i po
  partii, zamknięcie i Wiadomości, a także oba klienty realtime. Nie
  wysyłano wiadomości ani połączeń do osób spoza kont próbnych.
- **Ustawienia:** końcowa próba pola subskrypcji potwierdza zachowanie
  kategorii i fokusu po podmianie placeholdera na listę. Konto bez tabel
  zachowuje lokalne kategorie i objaśnienie. Anulowano bez zapisu profilu.

### Dodatkowy rzeczywisty błąd znaleziony w próbach

Odtworzenie zapisu Scrabble przekraczało przyznany przez serwer limit
pojedynczego wpisu stosu: kod brał żądane 16384 B, a sesja dostała 1536 B.
Podział archiwum korzysta teraz z faktycznych `Session#limits`, przed
utworzeniem checkpointu. Sześć celowanych skryptów oraz ponowne odtworzenie
tego samego zapisu i dalsze ruchy na dwóch kontach są poprawne. Bez zmiany
protokołu, formatu archiwum lub limitów serwera.

### Granice dowodu i stan pozostawiony użytkownikowi

Próby sterowały prawdziwymi kontrolkami i API przez MCP oraz ograniczone
pomocniki wejścia. To cztery konta na jednym komputerze/łączu, nie fizyczna
klawiatura, mysz, odsłuch ani wszystkie możliwe kombinacje. Pierwsze błędy
pomocników, nieudane próby i poprawki produkcji są zachowane oddzielnie.

Nieukończona pozostaje ponowna zimna ścieżka wejścia przez widget: podczas
próby okno ELTEN-a nie było na pierwszym planie, więc prawidłowy strażnik
aktywności nie pobierał listy. Nie omijano go i nie zaliczono próby jako
sukces. Wcześniejsze odczyty Ctrl+W na aktywnym widgecie są osobnymi próbami.
Nie sprawdzono fizycznego odebrania połączenia konferencji, awarii całego
procesu ani wszystkich kombinacji prywatnych wariantów każdej gry.

Sondy, opóźnienia i własne aktywne partie usunięto. Do publicznego stołu
próbnego dołączyła osoba spoza testu: nie uruchomiono tam gry, opuściliśmy
stół bez zamykania go tej osobie; nie jest już zarządzany jako fixture.
Własny próbny zapis Scrabble usunięty. Profile i instalacje na dysku bez
zmian. Cztery kopie otrzymały przez zwykły reload 245 aktualnych źródeł,
tłumaczenia i audio; hash zestawu Ruby:
`60695b61482f799cbf953d8b43ecb36d5712096a6c25e830ed541f8d4e1f4d38`.

Dowody prywatne: `diagnostics/current-plan-20260927/`, szczególnie
`LIVE_COVERAGE.md`, `LIVE_PROGRESS_28.md`, pliki `PAIR-*`, `MCP-*` i końcowe
`MCP-final-{cleanup-probes,current-sources,runtime-snapshot}-*`.
Pełny następny przegląd kodu jest osobnym zadaniem opisanym w
[AUDIT_AFTER_CURRENT_PLAN.md](AUDIT_AFTER_CURRENT_PLAN.md).

## Aktualizacja robocza — 27 września, po pierwszych partiach

- Punkt 3: dodano wspólną granicę oczekującej operacji z zachowaniem
  nawigacji, bezpiecznych odczytów, pomocy, szkicu czatu i lokalnego ruchu
  paletki. Zapis nadal jest autorytatywny; nie kolejkuje kolejnego zagrania.
  Pierwsza prawdziwa partia Czwórek na dwóch kontach zakończona siedmioma
  ruchami. Próby opóźnień 3 i 10 s zachowały pojedynczy zapis, nowy szkic,
  fokus, pomoc i odbiór za otwartymi Wiadomościami. To nie kończy macierzy
  pozostałych powierzchni, awarii i czterech klientów realtime.
- Punkt 6: wspólne menu użytkownika działa dla człowieka z rzeczywistej
  listy. Sprawdzono aktywną i zakończoną partię, natywne menu oraz wejście
  w Wiadomości i odświeżanie w tle. Poczekalnia i realtime jeszcze w toku.
- Punkt 4: poprawiona geometria warcabów 8/10/12. Na dodatkowe polecenie
  użytkownika usunięto roboczą gałąź zgodności dawnych współrzędnych —
  zostaje tylko poprawny układ. Testy numeracji i odtwarzania nowej gry
  są poprawne; stare pozycje regresji reguł i bota wymagają przeniesienia.
  Próby żywe oraz dodatkowe układy bić pozostają do wykonania.
- Punkt 5: przycięto dokładnie pierwsze 3 s standardowego audio_ball_up,
  odtworzonego z pierwotnego pliku i dotychczasowego przetwarzania. Długość
  8,134875 → 5,134875 s, mono/48 kHz/Opus 144 VBR/20 ms. Pomiar pozostałego
  fragmentu: różnica RMS około -0,0013 dB. Audiodisc nietknięty. Natywne
  odtwarzanie i pętla jeszcze niepotwierdzone; pomiar nie zastępuje odsłuchu.
- Punkt 2: lokalne metadane wpisów Chińczyka przechowują historyczne miejsca
  i nicki; filtr kolorów obejmuje mowę, turę, wynik i historię. Dane zdarzeń
  nie są przepisywane. Test prezentacji PL/EN zaliczony; próby żywe w toku.
- Punkty 1 i 7: robocza publikacja aktywności w tle z minutowym ograniczeniem,
  filtr tylko list publicznych oraz opcjonalny opis ról i Ctrl+W. Odczyt
  wykorzystuje refresh discovery, bez dołączania. Nowe testy sprawdzają
  nieznaną/ukrytą/niezgodną obsadę, nazwane boty, limit 1024 B, jedną zaległą
  publikację, granicę 45 minut i odrzucanie spóźnionych odpowiedzi widoku.
  Nie ma jeszcze dowodu z żywych kont dla tych dwóch punktów.
- Pierwsze niepowodzenia zachowane: błędna atrapa argumentów w kontakcie
  widgetu, dwie pomyłki danych pomocników testów oraz ścieżka require nowego
  czytnika. Zostały poprawione; ponowienia są raportowane oddzielnie.
- Cztery hosty mają co najmniej API 3.0.4. Do pamięci wczytano 245 źródeł
  (SHA-256 zestawu 81571e186e6f487923e8573cc5d9ac839f71932b50d8f0a47de381f6e1373db0),
  tłumaczenia i audio. Po usunięciu starej geometrii potrzebny jest jeszcze
  kolejny hotload. Nie zmieniano instalacji ani wersji hostów.

Poniższy opis etapu 3.6 jest historycznym stanem pierwszego etapu.

## Etap 3.6 — dostęp do tabel, lobby i ustawienia

- Odtworzono blokadę: zatrzymana odpowiedź tabeli blokowała także lokalny
  odczyt jej uchwytu i reset kontekstu. Pierwsza próba
  `server_tables_concurrency_test.rb` zakończyła się oczekiwanym błędem
  `local table lookup waited for a network response`.
- Rozdzielono krótką blokadę pamięci i szeregowaną pracę sieciową. Generacja
  dostępu chroni nowy kontekst przed spóźnionym wynikiem i starą odmową.
- Po zmianie: pięć przypadków współbieżności i istniejący
  `server_tables_test.rb` poprawne. Lobby czyta historię w skończonym zadaniu
  w tle, a ustawienia współdzielą odczyt subskrypcji bez zatrzymywania
  lokalnych kategorii. Nieznana lista nie jest zapisywana jako pusta.
- Siedem celowanych skryptów zaliczonych: `server_tables_concurrency_test`,
  `server_tables_test`, `lobby_background_test`, `settings_background_test`,
  `settings_table_access_test`, `table_watch_runtime_test` i
  `development_table_access_test`. Nie uruchamiano pełnego runnera.
- Żywe próby na obu kontach: rzeczywiste formularze i API, z dodaną na czas
  próby trzysekundową zwłoką odczytu. Nawigacja i ustawienia lokalne działały
  podczas oczekiwania; na głównym koncie odczyty trwały około 3,04 s poza
  wątkiem UI. Lokalny odczyt cache podczas zablokowanej operacji sieciowej
  trwał 0,014 ms. Konto testowe bez dostępu do tabel zachowało kategorie
  lokalne i objaśnienie niedostępności subskrypcji.
- Sprawdzono anulowanie i ponowne otwarcie ustawień, zachowanie kategorii
  i fokusu oraz późny wynik po zamknięciu. Pierwsza sonda wskazywała inne
  pole powiadomień; dodatkowa próba objęła właściwe pole subskrypcji.
  Drobne końcowe czyszczenie fokusu wymienianego pola ma już testy lokalne,
  lecz wymaga jeszcze powtórzenia na żywo.
- Dowody: `diagnostics/current-plan-20260927/`. To handlery prawdziwych
  kontrolek na jednym komputerze, nie fizyczna klawiatura, odsłuch ani partie.
  Sondy przywrócono, sztuczne opóźnienia usunięto, własne puste lobby zamknięto.
  Pozostałe części punktu 3 (operacje partii, szkic czatu i realtime) są
  niewdrożone; ten etap nie oznacza ukończenia całego punktu.

## Środowisko żywych prób

Główna kopia zgłasza ELTEN 3.0.5 RC1, kopia testowa 3.0.4; obie spełniają
minimum. Kopię testową uruchomiono zwykłym skryptem i odnowiono sesje MCP.
Nie aktualizowano niepotrzebnie hostów. Do obu wczytano 242 bieżące źródła
bez instalacji paczki (SHA-256 zestawu 7ab0280ea8c2b2862f2ea317aeed258ccec1a617c972e27c1051984d63fdc6cc).
Końcowa drobna korekta fokusu nastąpiła po tym wczytaniu. Prób partii
jeszcze nie rozpoczęto.
