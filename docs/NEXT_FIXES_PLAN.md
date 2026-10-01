# Nowy plan poprawek Game Roomu

Ustalenia z 1 października 2026. Status: wszystkie dziesięć punktów wdrożone;
testy celowane i próby na żywych kontach zakończone. Wydanie: 2.0.4.3/242.
Punkt 7 uwzględnia korekty użytkownika do zaproponowanego zakresu powiadomień.
Punkt 8 obejmuje zatwierdzony wariant drużynowego Tysiąca z czterokartowym
musikiem i rozliczeniem poddania rozdania. Punkt 9 wskazuje dźwięk informacji
o odrzuceniu zaproszenia. Punkt 10 przewiduje zmianę nazwy programu
z „ELTEN Game Room” na „Power Games”.
To nowy plan, nie ponowienie wcześniej zakończonych poprawek.

### Wynik wdrożenia

51 różnych celowanych skryptów ma końcowy wynik poprawny (kilka etapów,
nie pełny runner). Pierwsze niepowodzenia zachowano w raportach. Próby
na czterech rzeczywistych kontach objęły pełny obieg pauz Tysiąca,
rozgrywki drużynowe, boty, zastępstwa oraz zapis i wznowienie w nowej sesji.
Sprawdzono również dotychczasowe warianty dwu- i trzyosobowy.

Na żywo sprawdzono formularze Krowy, jej ponowne rozpoczęcie po obu
zakończeniach, ustawienia Ponga i Audio Balla przed partią i podczas niej,
wybór drużyn, odczyt ustawień bez dołączania, zmianę ustawień i zamknięcie
wybranego stołu oraz publiczne/prywatne zaproszenia i ogłoszenie nowego stołu.
Odrzucenie uruchomiło nowy zasób audio po jednym razie u każdego nadawcy.
Dwa konta równocześnie otrzymały to samo przypisanie Dziennej Krowy mimo
odwrotnej kolejności słownika; historię i granicę dnia sprawdzono osobno.

To jeden komputer i jedno łącze, wejście przez natywne handlery i formularze,
rzeczywiste API/relay; nie odsłuch ani fizyczna klawiatura na czterech komputerach.
Rzadkie kombinacje rozliczeń (beczka, zera, kolejne poddania) pokrywają
deterministyczne testy lokalne, nie wielogodzinne naturalne mecze.
Serwer zachował dotychczasową ochronę i dane; dodano docelową tabelę
przypisań dnia, usunięto pustą nieużywaną tabelę pomiarową oraz własne próby.
Szczegóły prywatne: `diagnostics/power-games-plan-20261001/` w workspace.

## 1. Stałe przypisanie słowa do dnia

Krowa nadal korzysta z jednego wspólnego słownika we wszystkich wariantach.
Każde słowo ma stały identyfikator, którego dodanie kolejnych słów nie zmienia.
Identyfikatora nie wolno utożsamiać ze zmienną pozycją na liście słów.

W Dziennej Krowie słowo jest przypisane do konkretnego dnia raz i pozostaje
takie samo dla wszystkich graczy. Granicą dnia jest północ czasu polskiego,
ustalana na podstawie czasu serwera, nie zegara komputera gracza. Aktualizacja
słownika w ciągu dnia nie zmienia już przypisanego słowa.

Nowe słowa uczestniczą od razu w następnym losowaniu:

- w Dziennej Krowie przy wyborze słowa na następny dzień;
- w pozostałych wariantach przy kolejnym losowaniu, np. podczas tworzenia
  partii, przelosowania słowa albo rozpoczęcia następnej rundy.

Nie tworzymy osobnego, zamrożonego słownika Dziennej Krowy ani ręcznych dat
aktywacji nowych słów. Trwająca zagadka zachowuje swoje rozwiązanie.

Ranking odczytuje zapisane przypisanie dnia do słowa, zamiast ponownie
wyliczać je z aktualnej liczby słów. Same stałe identyfikatory nie wystarczą:
trzeba również utrwalić wynik losowania. Przed wdrożeniem należy ustalić
obsługiwany przez serwer sposób wspólnego, trwałego zapisu, odporny na
równoczesne rozpoczęcie gry przez kilka osób. Nie może on ujawniać dzisiejszego
rozwiązania w zwykłym interfejsie. Użytkownik zaakceptował zaszyfrowany
zapis odczytywany przez klienta: chroni przed przypadkowym ujawnieniem,
ale nie przed osobą analizującą kod i dane aplikacji.

Przy naprawianiu istniejącej historii nie wolno zgadywać rozwiązania na
podstawie obecnego słownika. Starsze wersje mogły wybrać różne słowa dla
tego samego dnia; korekta wymaga potwierdzenia faktycznie rozgrywanej zagadki.

Miejsca do zmiany: repozytorium słów i dostawca dziennej zagadki w
`games/krowa_support/`, zapis danych dnia oraz odczyt rankingu. Zachować
istniejący zapis sekretu trwającej partii i ograniczenie jednej gry dziennej.

## 2. Ustawienia Krowy pod Ctrl+P i w menu stołu

Ustawienia Krowy otwieramy skrótem Ctrl+P oraz pozycją w menu stołu,
w tym samym miejscu i według tej samej zasady co w Axel Pongu i Audio Ballu.
Usuwamy przycisk ustawień z kolejności przechodzenia Tabem oraz zastępujemy
dotychczasowy skrót Ctrl+D. Obie nowe drogi otwierają ten sam formularz.

Uaktualnić pomoc i opis sterowania. Skorzystać ze wspólnego mechanizmu
ustawień lokalnych gier, bez dokładania osobnej ścieżki tylko dla Krowy.
Punkty wejścia są obecnie w `games/krowa.rb` oraz
`games/krowa_support/presentation.rb` i `client.rb`.

## 3. Galeria poza trwającą partią

Galeria Krowy jest dostępna przed rozpoczęciem partii i po jej zakończeniu.
Podczas aktywnej partii nie można jej otworzyć, aby nie służyła jako źródło
podpowiedzi. Ograniczenie obejmuje wszystkie drogi wejścia, a nie tylko
widoczność przycisku. Nie usuwa zgromadzonych słów ani nie zmienia zasad
zapisywania nowych pozycji w galerii.

## 4. Ponowne rozpoczęcie Krowy przy tym samym stole

Po odgadnięciu słowa lub poddaniu się w wariancie Losowe słowo ma być
dostępne „Rozpocznij grę”. Kolejna partia rusza przy tym samym stole,
bez konieczności tworzenia pokoju od nowa.

Sprawdzić również pozostałe zakończenia i warianty Krowy, aby przycisk był
dostępny tam, gdzie wolno rozpocząć następną partię. Nie omijać ograniczenia
Dziennej Krowy ani innych celowych ograniczeń wariantów. Nowa partia ma
własne słowo i próby, bez przenoszenia zakończonej zagadki.

Punkt wyjścia: oznaczenie `restartable` w
`games/krowa_support/presentation.rb` oraz wspólna obsługa rozpoczęcia gry.

## 5. Czytelne etapy wyboru drużyn

Poprawka dotyczy wspólnego interfejsu gier drużynowych, nie dodania drużyn
do Krowy. Gdy trzeba jeszcze zatwierdzić skład, kolejność i etykiety mają być
następujące:

1. Przy stole: „Wybierz drużyny”, zamiast mylącego „Rozpocznij grę”.
2. W oknie wyboru: „Zaakceptuj drużyny”, zamiast „Przyjmij”.
3. Po zatwierdzeniu i powrocie do stołu: „Rozpocznij grę”.

Zatwierdzenie drużyn zapisuje skład, ale samo nie rozpoczyna partii.
Zachowujemy losowanie i ręczne ustawianie drużyn oraz zapamiętany skład
po zakończeniu gry. Jeśli skład jest nadal poprawny i zatwierdzony,
nie wymagamy ponownego wyboru przed każdym rozpoczęciem.

Punkt odniesienia: wspólny formularz drużyn i kontrakt opisany w
[Drużynach, rolach i fokusie](TEAMS_ROLES_AND_FOCUS.md).

## 6. Ctrl+R przed wejściem do stołu

Ctrl+R odczytuje wariant i ustawienia zaznaczonego stołu także na widgecie
oraz na liście stołów w „Dołącz do stołu”, po wybraniu gry. Użytkownik może
poznać zasady stołu przed dołączeniem do niego.

Wykorzystać ten sam sposób opisywania wariantu i ustawień co pod Ctrl+R
wewnątrz stołu, bez tworzenia osobnych opisów dla każdej z tych list.
Odczyt nie dołącza użytkownika do stołu, nie zmienia zaznaczenia ani
dotychczasowego opisu pozycji na liście. Przy braku zaznaczonego stołu,
jego zniknięciu lub niedostępnych ustawieniach podać odpowiedni komunikat,
bez zgadywania wartości. Pobieranie brakujących danych nie może blokować
interfejsu ani powodować dodatkowych żądań przy każdym ruchu strzałką.

Uzupełnić pomoc obu list o nowy skrót.

## 7. Krótki wariant w powiadomieniach o stołach i zaproszeniach

Powiadomienie o nowym stole i zaproszenie korzystają z tego samego krótkiego
opisu wariantu. Opis obejmuje wyłącznie wskazane informacje, nie jest kopią
pełnego Ctrl+R ani obecnego podsumowania wszystkich ustawień. Pełne ustawienia
pozostają dostępne na żądanie pod Ctrl+R, także przed wejściem dzięki punktowi 6.

Korekty zakresu wskazane przez użytkownika:

- Spades: tylko wariant, np. „Quicksand”. Bez dopisku o drużynach, limicie
  punktów czy botach.
- Poker: tylko odmiana, np. „Texas Hold'em” albo „dobierany”. Bez sposobu
  licytacji, stawek czy liczby żetonów.
- Państwa-miasta: tylko język odpowiedzi, bez zestawu kategorii.
- Bez żadnego dodatkowego opisu: Mexican Train, Wojna, Wojna naukowa,
  Statki, Chińczyk, Reversi, Yahtzee i Biblios.

„Bez dodatkowego opisu” nie usuwa samego powiadomienia, nazwy gry,
nadawcy ani informacji, czy chodzi o nowy stół, czy zaproszenie. Nie
zastępować pominiętych szczegółów dopiskiem „standardowe zasady”.

Pozostałe gry zachowują zakres z ostatniej propozycji:

- Makao: wybrany zestaw zasad, np. „rozszerzone” lub „własne zasady”.
- UNO: talia klasyczna, Flip lub No Mercy oraz z przechwytywaniem albo bez.
- Axel Pong: singiel albo debel, tryb klasyczny albo arcade i trudność.
- Audio Ball: poziom trudności; nie dodawać jedynego obecnie trybu „klasyczny”.
- Krowa: wariant oraz długość słowa, jeżeli jest wybierana w tym wariancie.
- Warcaby: rozmiar planszy; sam rozmiar nie jest deklaracją pełnego
  standardowego zestawu reguł.
- Tysiąc: wybrany wariant; w dwuosobowym także wielkość musików.
  Po wdrożeniu punktu 8 uwzględnić również czteroosobowy i drużynowy,
  bez rozwijania ich zasad w powiadomieniu.
- Remik: zwykły albo eliminacyjny oraz z manipulowaniem układami albo bez.
- Domino: zestaw kostek i indywidualnie albo drużynowo.
- Quiz i Taboo: język rozgrywki oraz nazwa zestawu, bez liczby pytań lub kart.
- Scrabble: język słownika.
- Monopoly: wybrana plansza.
- Mankala: nazwa odmiany.
- Farkle oraz Cat, Head, Tail: limit punktów.
- 99: początkowa liczba żetonów.
- 3-5-8: z wymianą kart albo bez.
- Szachy, Czwórki oraz Kółko i krzyżyk: bez dodatkowego opisu.

Nie dodawać automatycznie wszystkich opcji odbiegających od domyślnych.
Nie dopisywać opóźnienia bota, transportu/P2P, ustawień dźwięku ani pełnej
listy kar i limitów. Nie nazywać zmodyfikowanych zasad „klasycznymi” tylko
dlatego, że nie mieszczą się w krótkim opisie. Długość ograniczać doborem
całych informacji, nie ucinaniem tekstu w połowie wyrazu.

Przykładowe brzmienie ogłoszenia: „Papierek, Axel Pong, debel, arcade,
trudny. Nowy stół”. W zaproszeniu ten sam krótki opis uzupełnia dotychczasową
informację o zapraszającym i stole. Zachować odróżnienie zwykłego zaproszenia
od wznowienia zapisanej partii i nie powtarzać nazwy gry lub typu powiadomienia.

Przy wdrażaniu gra wskazuje najważniejsze istniejące ustawienia, a wspólny
mechanizm formatuje opis dla obu typów powiadomień w języku odbiorcy.
Przesłać potrzebne, niesekretne wartości razem z powiadomieniem. Jego odbiór,
odczyt i wyświetlenie nie mogą wywoływać dodatkowego pobierania stołu ani
blokować interfejsu. Opis odpowiada ustawieniom z chwili wysłania;
bieżące ustawienia sprawdza odczyt Ctrl+R. Brak danych nie oznacza wariantu
domyślnego. Zachować obecne filtry, dźwięki, ważność i czyszczenie powiadomień.

## 8. Tysiąc czteroosobowy i drużynowy

Dodać dwa osobne warianty, zachowując dotychczasowy dwu- i trzyosobowy.

Wariant czteroosobowy działa tak jak obecna gra trzyosobowa, ale w każdym
rozdaniu jedna osoba pauzuje. Pauza przechodzi co rozdanie na kolejną osobę;
po pełnym obiegu każdy pauzował raz. Trzej pozostali gracze korzystają
z dotychczasowych zasad rozdania, musika, licytacji, przekazywania kart,
rozgrywania lew i rozliczania wyniku.

Pauzująca osoba pozostaje graczem przy stole, nie zmienia się w obserwatora.
Nie bierze udziału w decyzjach bieżącego rozdania. Interfejs i komunikaty
powinny jasno wskazywać, kto aktualnie pauzuje, i uwzględniać jego powrót
w następnym rozdaniu. Nie dodawać osobnych premii za pauzę bez uzgodnienia.

Wariant drużynowy ma dwie stałe drużyny po dwie osoby, siedzące naprzemiennie.
Wszyscy czterej uczestniczą w każdym rozdaniu, bez pauzy. Każdy widzi tylko
własne karty. Do ustawienia par wykorzystać istniejący wspólny wybór drużyn.
Użytkownik zatwierdził następujące zasady:

- Rozdajemy po 5 kart i odkładamy 4 karty do musika. Zwycięzca licytacji
  zabiera cały musik, a następnie przekazuje po jednej karcie każdej
  pozostałej osobie, również partnerowi. Do rozgrywania lew każdy ma 6 kart.
- Licytują wszystkie cztery osoby. Zwycięzca zobowiązuje swoją drużynę
  do zdobycia wylicytowanej liczby punktów. Partner może przebić jego ofertę;
  pozostają dotychczasowe reguły pasa. Limit licytacji wynika z meldunków
  we własnej ręce, bez uwzględniania ukrytych kart partnera.
- Wynik jest wspólny dla pary. Sumujemy punkty z lew i meldunków obu osób.
  Drużyna zwycięzcy licytacji otrzymuje wartość kontraktu, jeśli go wykona,
  albo traci tę wartość, jeśli go nie wykona. Przeciwnicy dopisują własne
  zdobyte punkty, z dotychczasowym zaokrąglaniem. Wynik zapisujemy raz
  dla drużyny, nie osobno i podwójnie dla każdego partnera. Przykład:
  kontrakt 150 i zdobyte 170 daje +150; zdobyte 140 daje -150.
- Zachowujemy obecne zasady: trzeba dołożyć do koloru, a przy jego braku
  zagrać atut, jeśli się go ma. Nie ma obowiązku przebijania wyższą kartą.
  Obowiązuje to również wtedy, gdy lewę wygrywa partner; użytkownik
  wyraźnie potwierdził zachowanie obecnych zasad w wariancie drużynowym.
- Meldunek wymaga króla i damy w ręce jednej osoby, a jego zgłoszenie
  podlega dotychczasowym warunkom dotyczącym zagrywającego. Nie tworzymy
  meldunku z kart dwóch partnerów ani nie przenosimy prawa do meldowania
  automatycznie z partnera na drugą osobę.
- Beczka i licznik zer są wspólne dla drużyny. Brak punktów jednego
  partnera nie jest zerem drużyny, jeśli drugi zdobył punkty. Cel punktowy
  i zwycięstwo dotyczą pary, a nie pojedynczej osoby.

Zatwierdzone rozliczenie poddania rozdania traktuje drużynę jako jednego
uczestnika:

- Poddać może zwycięzca licytacji po obejrzeniu musika, ale przed
  przekazaniem pierwszej karty.
- Przeciwna drużyna otrzymuje połowę wylicytowanej wartości, minimum
  60 punktów, zaokrągloną w górę do wielokrotności pięciu. Premię
  przyznajemy raz całej parze, bez mnożenia przez liczbę partnerów.
- Pierwsze i drugie poddanie nie odejmują punktów poddającej się drużynie.
  Co trzecie poddanie oznacza -120 punktów. Licznik jest wspólny dla pary,
  niezależnie od tego, który partner wygrał licytację i poddał rozdanie.
  Nie odejmujemy dodatkowo wartości niewykonanego kontraktu.
- Drużyna na beczce nie może poddać rozdania. Przeciwnicy będący na beczce
  nie otrzymują premii, a poddanie nie zużywa ich próby na beczce.
- Poddania nie liczymy dodatkowo jako rozdania z zerowym wynikiem.

Przykład: poddanie przy kontrakcie 150 daje przeciwnikom 75 punktów,
o ile nie są na beczce. Poddająca się para zachowuje wynik, chyba że
to jej trzecie poddanie w cyklu — wtedy traci 120 punktów.

Przy wdrażaniu rozszerzyć obecną grę, nie tworzyć drugiej implementacji
Tysiąca. Rozdzielić stałą obsadę stołu od uczestników danego rozdania;
uwzględnić boty, zapis i odtworzenie oraz zmianę osoby zajmującej miejsce.
Uzupełnić wybór wariantu, zasady, pomoc i opis ustawień.

## 9. Dźwięk informacji o odrzuceniu zaproszenia

Przy informacji dla nadawcy, że zaproszenie zostało odrzucone, odtwarzać
wybrany przez użytkownika plik:

`C:/Users/mateu/Documents/Freesound/110931_error2_preview-hq-ogg.ogg`

Dźwięk ma towarzyszyć istniejącemu zdarzeniu odrzucenia i jego wpisowi
w historii. Nie tworzyć z tego powodu nowego powiadomienia systemowego
ani pustego wpisu. Nie zmieniać dźwięków otrzymania zaproszenia i nowego
stołu. Odtwarzać go raz przy otrzymaniu odrzucenia, zgodnie z ustawieniami
głośności i wyciszenia, nie ponownie przy odświeżaniu lub czytaniu historii.
Przy wdrażaniu przygotować zasób według obowiązujących zasad audio projektu;
nie nadpisywać wskazanego nagrania źródłowego.

## 10. Zmiana nazwy programu na Power Games

Zmienić nazwę widoczną dla użytkowników z „ELTEN Game Room” na „Power Games”.
Stosować tę samą nazwę we wszystkich językach interfejsu. Uwzględnić oba
manifesty (`manifest.json` i nagłówek `__app.rb`), menu programów ELTEN-a,
tytuły okien, nazwę widgetu, komunikaty, pomoc oraz bieżące opisy programu.
Przy kolejnym wydaniu uwzględnić nową nazwę w nazwie paczki i danych
publikowanego programu, zachowując zgodność obu manifestów.

To zmiana nazwy istniejącej aplikacji, nie utworzenie nowego programu.
Zachować jej identyfikator, autora i podpis, powiązania z serwerem, tabele,
statystyki, subskrypcje, ustawienia i zapisy partii. Nie zmieniać z tego
powodu technicznych nazw klas, kluczy ustawień ani katalogów danych.
Nie wykonywać bezmyślnej podmiany każdego wystąpienia „Game Room”:
historyczne wpisy, nazwy zewnętrznych projektów i adresy pozostają poprawne.
Zmiana nazwy repozytorium GitHub lub grupy ELTEN-a nie należy do tego punktu.

## Sprawdzenie podczas wdrażania

Każdy dotknięty mechanizm sprawdzić lokalnie oraz na żywych kontach,
w liczbie odpowiedniej do scenariusza. W szczególności:

- Dodanie słów nie zmienia dzisiejszej zagadki, trwających partii ani
  wcześniejszych przypisań. Nowe słowa są kandydatami od następnego losowania.
  Dwa konta otrzymują tę samą dzienną zagadkę, także przy równoczesnym starcie.
  Sprawdzić granicę dnia i brak ujawnienia rozwiązania przed czasem.
- Ctrl+P i menu stołu otwierają te same ustawienia Krowy; Tab nie odwiedza
  usuniętego przycisku. Skróty i ustawienia Ponga oraz Audio Balla nadal działają.
- Galeria działa przed partią i po niej, lecz nie daje się otworzyć podczas gry.
- Po odgadnięciu i po poddaniu się można zacząć kolejną losową zagadkę
  bez opuszczania stołu. Dzienna Krowa nadal pilnuje limitu rozpoczęć.
- Wybór, anulowanie i zatwierdzenie drużyn mają właściwe etykiety i skutki;
  akceptacja nie uruchamia meczu, a poprawny skład pozostaje zapamiętany.
- Ctrl+R na widgecie i w „Dołącz do stołu” odczytuje ustawienia właściwego
  stołu, zgodne z odczytem po wejściu. Sprawdzić również zmianę ustawień przez
  gospodarza, pustą listę i zniknięcie stołu. Sam odczyt nie tworzy członkostwa
  ani nie zmienia fokusu.
- Dla punktu 7 sprawdzić oba rodzaje powiadomień, zaproszenia
  publiczne i prywatne oraz wznowienie partii. Opis tej samej konfiguracji
  ma być spójny, krótki i przetłumaczony dla odbiorcy. Sprawdzić brakujące
  dane, długie nazwy zestawów, zmianę ustawień po wysłaniu oraz brak nowej
  pracy sieciowej podczas prezentacji powiadomienia. Gry oznaczone jako
  „bez dodatkowego opisu” nie mogą otrzymać szczegółów przez ogólny formatter;
  Spades nie dopisuje drużyn, Poker licytacji, a Państwa-miasta zestawu kategorii.
- Tysiąc czteroosobowy: pełny obieg czterech rozdań i rotacja pauzy,
  pomijanie pauzującego w licytacji i lewach, rozliczenie i kolejna partia.
  Sprawdzić graczy oraz boty, zapis/odtworzenie i zastąpienie uczestnika.
  Osobno potwierdzić niezmienione działanie wariantów dwu- i trzyosobowego.
- Tysiąc drużynowy: cztery osoby, po 5 kart i musik 4, następnie po 6 kart
  bez zgubienia lub podwojenia którejkolwiek karty. Sprawdzić przekazanie
  także partnerowi, przebicie jego oferty, pas, dokładanie do koloru i atut
  bez obowiązku zagrania wyższej karty oraz meldunek wyłącznie z własnej ręki.
  Potwierdzić sumowanie punktów pary, wykonany i przegrany kontrakt,
  zaokrąglanie wyniku przeciwników, wspólną beczkę, zera i zwycięstwo.
  Boty mają uwzględniać współpracę bez dostępu do ukrytej ręki partnera.
  Sprawdzić zapis/odtworzenie i zastępstwo człowieka lub bota bez zmiany
  drużyny zajmowanego miejsca. Dla poddania sprawdzić minimum 60, połowę
  kontraktu i zaokrąglanie w górę, wspólny licznik przy naprzemiennym
  poddawaniu przez partnerów, karę co trzecie poddanie, oba przypadki beczki
  i brak dodatkowego zera lub kary za niewykonanie kontraktu. Warianty
  indywidualne nadal liczą wyniki osobno.
- Odrzucenie zaproszenia publicznego i prywatnego dociera do nadawcy
  wraz z właściwym dźwiękiem i wpisem historii, bez nowego powiadomienia
  systemowego. Sprawdzić jednokrotne odtworzenie, ustawienia głośności
  i wyciszenia oraz brak ponownego dźwięku po odświeżeniu lub powrocie.
  Otrzymanie zaproszenia i ogłoszenie nowego stołu zachowują swoje dźwięki.
- Power Games jest nazwą tej samej aplikacji po aktualizacji, nie drugą
  instalacją. Sprawdzić oba manifesty, menu, widget, okna i tłumaczenia,
  zachowanie dotychczasowych ustawień, makr, subskrypcji, statystyk i zapisów,
  a także uruchamianie oraz dołączanie przez widget i zaproszenia.

Przy wdrożeniu uzupełnić odpowiednie teksty PL/EN i pomoc. Po testach
przebudować i podpisać wersję 2.0.4.3, build 242, uzupełniając changelog.
