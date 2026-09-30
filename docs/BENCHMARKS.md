# Lokalne benchmarki

```console
mkdir tmp
ruby tools/benchmark-runtime.rb --iterations 20 --output tmp/benchmark.json
ruby tools/benchmark-runtime.rb --games spades,monopoly,uno --iterations 20 --output tmp/subset.json
```

Katalog `tmp/` przygotuj, jeśli jeszcze nie istnieje; jego zawartość jest ignorowana przez Git.

Wejściem jest wersjonowany korpus `test/fixtures/contracts/v1/histories.json`.
Raport zapisuje jego hash, wersję Ruby i platformę. Każda faza ma rozgrzewkę,
liczbę iteracji, czas CPU, czas ścienny i liczbę alokacji. Replay, głęboka kopia,
budowa specyfikacji widoku, legalne akcje i decyzja bota są mierzone osobno.
Digest decyzji obejmuje wybraną akcję i dalszy stan RNG; porównanie szybkości
ma sens dopiero po potwierdzeniu zgodności tych wyników.

Pomiar pustej blokady jest osobną pozycją. Nie mierzy oczekiwania na planera,
sieci, dysku, hosta ani syntezatora. Nie należy odejmować go od RTT ani
interpretować lokalnego czasu CPU jako opóźnienia gracza. Kolejki i relay
wymagają osobnych scenariuszy realtime, a rzeczywiste różne łącza — prób
klientów na tych łączach.

Porównuj tę samą wersję Ruby, platformę, korpus i liczbę iteracji, po kilku
przebiegach bez równoległego runnera. Brak progu czasu w CI jest celowy:
zmienność współdzielonego hosta nie może udawać regresji reguł gry.
Raport zawiera wynik ostatniej iteracji; wzorce decyzji i replayów kontrolują
osobno `model_contract_test.rb` oraz `test/games/spades/decision_contract_test.rb`.
