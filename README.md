# ELTEN Game Room

ELTEN Game Room to dostępny zestaw gier wieloosobowych działający jako program
dla ELTEN-a. Repozytorium zaczyna historię od opublikowanej wersji **1.1.0,
build 176**. Kod aplikacji, tłumaczenie i dźwięki w tym pierwszym stanie są
bezpośrednią kopią tego buildu.

Szczegóły pochodzenia i sumę podpisanej paczki zapisano w
[BASELINE.md](docs/BASELINE.md).

## Gry

Obecny rejestr obejmuje 32 gry: 3-5-8, 99, Audio Ball, Axel Pong, Biblios,
Chińczyk, Czwórki, Domino, Farkle, Kot/głowa/ogon (Cat, head, tail),
Kółko i krzyżyk, Krowa, Makao, Mancala, Mexican Train, Monopoly,
Państwa-miasta, Poker, Quiz Party, Remik, Reversi, Scrabble, Spades,
Statki, Szachy, Taboo, Tysiąc, UNO, Warcaby, Wojna, Wojna naukowa i Yahtzee.

Program zawiera wspólny szkielet stołów, historii, dostępnych plansz i innych
powierzchni gry, skrótów klawiszowych, reguł, botów, punktacji oraz komunikacji
przez LiveSessions. Pong i Audio Ball używają dodatkowo wspólnej warstwy
Communications do zdarzeń w czasie rzeczywistym; trwały wynik pozostaje
w LiveSessions. Nowa gra powinna wykorzystywać istniejące elementy zamiast
budować osobny interfejs i transport.

## Wymagania

- ELTEN 3.0.4 lub nowszy dla bieżących źródeł;
- Ruby 4.0 do uruchamiania lokalnych testów;
- źródła zgodnej wersji ELTEN-a do testów kontraktów natywnego hosta;
- środowisko budowania ELTEN-a, jeśli chcesz utworzyć paczkę `.eltsetup`.

Sama aplikacja nie używa zewnętrznego pliku konfiguracyjnego ani prywatnych
kluczy. Łączy się z zadeklarowaną aplikacją serwerową ELTEN-a.

## Testy

Zainstaluj narzędzia tłumaczeń (`bundle install --gemfile tools/Gemfile.i18n`).
Ustaw `ELTEN_HOST_SOURCE` na katalog źródeł ELTEN-a zawierający `src/`.
W katalogu repozytorium uruchom:

```console
ruby tools/run-tests.rb --report test-results.json
```

Każdy test jest również samodzielnym skryptem Ruby, więc można uruchomić tylko
wybrany plik, na przykład:

```console
ruby test/ninety_nine_test.rb
```

Runner uruchamia każdy skrypt w osobnym procesie, zbiera wszystkie błędy
i stosuje limit 180 sekund na skrypt (`--timeout` zmienia limit).
Brak wymaganych źródeł hosta nie jest zaliczonym testem. `--allow-skip`
jest wyłącznie jawną zgodą na pomijanie opcjonalnych prób, nie ustawieniem CI.
Pomocniki w `test/support/` nie powinny wykonywać scenariuszy innych testów.
Historyczne porównania quizu z pełnymi raportami dawnych audytów znajdują się
w `test/historical/` i nie należą do zwykłego przebiegu ani CI. Kontrole bieżących
zestawów, sum, korekt, podziału Wiedźmina i eksportu TXT pozostają w `test/`.
Mając oryginalne raporty, ustaw `GAME_ROOM_QUIZ_AUDIT_ROOT` na katalog zawierający
`quiz-factual-audit-220/` oraz `quiz-recovery-audit-after-221/`, a następnie uruchom:

```console
ruby tools/run-quiz-tests.rb --historical-audit
```

Bez tego ustawienia kontrole historyczne szukają raportów w sąsiednim
`../diagnostics/`. Jawnie wybrana kontrola z brakującymi raportami kończy się
błędem z listą plików, nigdy pozornym sukcesem. Raporty nie są pobierane,
publikowane ani dołączane do instalatora.
Szczegóły zakresu porządków: [MAINTAINABILITY_CLEANUP.md](docs/MAINTAINABILITY_CLEANUP.md).

## Praca nad kodem

Rosyjski interfejs i zestaw quizu opisuje
[RUSSIAN_LOCALIZATION.md](docs/RUSSIAN_LOCALIZATION.md).
Źródłem tłumaczeń są katalogi PO; pliki MO powstają ze wspólnego kompilatora.

Najważniejsze punkty wejścia:

- `__app.rb` — manifest, trwały rejestr użytkowników, rejestr gier i główna klasa programu;
- `games/` — reguły i modele poszczególnych gier;
- `lib/game_surfaces/` — wspólne kontrolki dostępnego pola gry;
- `lib/game_screen.rb` — wspólny ekran partii;
- `lib/live_session_store.rb` — odkrywanie sesji oraz wspólny stos stanu pokoju i partii;
- `lib/game_room_transport.rb` — zdarzeniowa fasada komunikacji LiveSessions;
- `lib/game_repository.rb` — zapis i odtwarzanie zdarzeń partii;
- `lib/game_bots.rb` oraz pliki `*_strategy.rb` — boty i strategie;
- `test/` — testy modeli, transportu, interfejsu i regresji.

Dokładniejszy opis znajduje się w [architekturze](docs/ARCHITECTURE.md), a
instrukcja dodawania gry w [ADDING_A_GAME.md](docs/ADDING_A_GAME.md).

## Budowanie paczki

Instrukcja tworzenia niepodpisanej i podpisanej paczki znajduje się w
[BUILDING.md](docs/BUILDING.md). Certyfikat i klucz autora nigdy nie powinny
trafić do repozytorium.

## Zgłoszenia i pull requesty

Przed zmianą przeczytaj [CONTRIBUTING.md](CONTRIBUTING.md). Zgłoszenie błędu
powinno zawierać numer buildu, kroki odtworzenia, oczekiwany rezultat i — jeśli
to możliwe — krótki fragment logu bez danych prywatnych.

## Licencja i zasoby

Kod ELTEN Game Room jest udostępniany na licencji GNU General Public License
version 3. Pełny tekst znajduje się w pliku [LICENSE](LICENSE). Pochodzenie i
odrębne warunki dodatkowych składników opisuje
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
