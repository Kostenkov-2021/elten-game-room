# Trening i ocena strategii botów

Kod w `tools/training/` działa poza aplikacją i nie trafia do instalatora.
Wyniki treningu nie są automatycznie przenoszone do strategii używanych przez graczy.

## Spades

Jedno CLI obsługuje trening i niezależną ocenę wybranych profili:

```console
ruby tools/spades.rb train --help
ruby tools/spades.rb train --profiles standard_team_p4_t2 --output candidate.json
ruby tools/spades.rb evaluate --report candidate.json --profiles standard_team_p4_t2 --output evaluation.json
```

Nazwy profili pochodzą z `SpadesLearning::ARRANGEMENT_PROFILES` w
`spades_training.rb`. Bez `--profiles` trening obejmuje wszystkie układy,
a ocena wszystkie profile z raportu. `evaluate` porównuje kandydata z
bieżącymi profilami runtime na innych ziarnach; domyślnie wykonuje też
osobną kalibrację obu strategii. Nie odtwarza historycznych buildów.

`train` zachowuje kampanie, walidację i końcowy zbiór holdout. Niedokończona
partia w holdout blokuje przyjęcie kandydata. Niedokończona ocena końcowa
lub jej kalibracja kończy polecenie kodem 2, błąd argumentów kodem 1. Wyjście JSON
trafia na stdout lub do nowego pliku `--output`; istniejący plik nie jest
nadpisywany. Komunikaty postępu trafiają na stderr.

`spades_workflow.rb` współdzieli porównania, kryteria przyjęcia i formatowanie
raportu. `spades_training.rb` zawiera macierz scenariuszy, arenę i trening.
Zmiana wag produkcyjnych wymaga osobnej edycji i weryfikacji; CLI ich nie zapisuje.

## Wspólne biblioteki

- `match_runner.rb`: pełna partia na `GameRoomSimulation::Environment`,
  strategie przypisane uczestnikom i jawny powód przerwania.
- `game_training.rb`: tablica wartości decyzji, self-play i turniej ze zmianą
  miejsc oraz raportami wyników; polityka ma serializację JSON.
- `learned_strategy.rb`: strategia ucząca się używana przez self-play,
  niedostępna po samym wczytaniu runtime.

Te biblioteki nie są grami ani osobnymi poleceniami CLI. Scenariusze regresji
są w `test/tooling/training_test.rb`, `test/games/spades/learning_test.rb`,
`test/games/spades/tool_test.rb` i testach symulacji. Pomocnik audytu Tysiąca
należy do `test/support/tysiac_audit.rb`.
