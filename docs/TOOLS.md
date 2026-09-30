# Narzędzia utrzymania

Katalog `tools/` zawiera 12 samodzielnych narzędzi. Nie należy do runtime ani do
instalatora. Polecenia uruchamiaj z katalogu głównego repozytorium.

| Narzędzie | Zastosowanie |
| --- | --- |
| `translations.rb` | Ekstrakcja, aktualizacja, tworzenie i kompilacja katalogów Gettext; `check` bez zapisu. [Instrukcja](TRANSLATIONS.md). |
| `compile-rulebooks.rb` | Generowanie reguł z `tools/data/rulebooks/` według `rulebook_sources.json`; `--check` bez zapisu. |
| `generate-krowa-nouns.rb` | Odtworzenie rzeczowników Krowy z `data/krowa_nouns.txt`; `--check` bez zapisu. [Pochodzenie](BUILDING.md#źródło-rzeczowników-krowy). |
| `build-scrabble-dictionaries.rb` | Budowanie słowników Scrabble EN/PL w `content/`; argument: katalog źródeł z `wordlist-20210729.txt` i `sjp/slowa.txt`. |
| `build-taboo-cards.rb` | Walidacja i budowanie kart Taboo EN/PL w `content/` z `content/taboo_editorial.txt`. |
| `build-quiz-pack.rb` | Walidacja pytań JSON i tworzenie wskazanego zestawu Quizu; opcje w `--help`. |
| `export-quiz-text.rb` | Czytelne kopie pytań Quizu w `docs/quiz-questions/`; `--check` bez zapisu. |
| `encode_audio.rb` | Kodowanie oryginału do Opus; argumenty: wejście, nowe wyjście, opcjonalnie FFmpeg i FFprobe. [Profil](BUILDING.md). |
| `generate-pong-echo.rb` | Generowanie efektu echa Ponga z deterministycznego PCM do Opus. |
| `stage-release.rb` | Jedyny interfejs stagingu: lista plików wykonawczych, weryfikacja zależności i snapshot SHA-256. [Procedura](BUILDING.md). |
| `benchmark-runtime.rb` | Powtarzalne pomiary CPU, alokacji, replaya, widoków i botów. [Metodyka](BENCHMARKS.md). |
| `spades.rb` | Trening i ocena profili botów Spades: `train` albo `evaluate`. [Użycie](BOT_TRAINING.md). |

`support/` zawiera biblioteki współdzielone przez te polecenia i testy.
`training/` zawiera symulację pełnych partii, trening i porównywanie strategii
poza aplikacją. Dane konfiguracyjne i licencje pozostają obok narzędzi.
`rulebook_option_chapters.json` przypisuje opcje do rozdziałów zasad;
ten indeks redakcyjny sprawdza `test/ui/rulebook_authoring_test.rb`.

Testy uruchamia [test/run.rb](../test/run.rb). Kontrole jakości i kompletności
tłumaczeń są zwykłymi testami; generator korpusu referencyjnego znajduje się
w `test/fixtures/`. Szczegóły: [TESTING.md](TESTING.md).

Historyczne aplikatory, audyty jednego wydania, stare strategie porównawcze
i aliasy poleceń zostały usunięte. Ich historia pozostaje w Git.
Nie uruchamiaj ponownie historycznej selekcji pytań.
Zmiana generatora nie upoważnia do zmiany jego danych lub audio.
