# Własność snapshotów

- Zdarzenia zaakceptowane przez magazyn są niezmienną historią. Projekcja
  uczestników i komunikaty historyczne mają osobne zastosowania.
- Runner posiada model wykonawczy. Publikacja do UI i planowanie otrzymują
  własne kopie przez `GameRoomSnapshot.copy`; UI nie edytuje modelu workera.
- Pierwsze `publish_view` odłącza `accepted_events` widocznego replaya od
  jego źródeł: podstawia własną, głęboko zamrożoną kopię tej listy. Lokalny
  `ViewRevision` wiąże gotową rewizję z dokładnie tą listą oraz tożsamością
  stołu/partii/epoki obsady. Podmiana listy lub skopiowanie replaya wymaga
  nowego przechwycenia; poprawki historii trafiają przez nowy replay/listę,
  nie mutację zamrożonego prefiksu. Reszta modelu nie jest zamrażana.
  Zwykłe `GameRoomSnapshot.copy` nadal zwraca mutowalną kopię, także dla
  przyrostowych reducerów. Token nie trafia do replaya, archiwum ani workera
  jako dowód aktualności zapisu; walidacja przed zapisem pozostaje świeża.
- Prezenter kopiuje również prefiksy. Dla wartości niedających się skopiować
  może jawnie odtworzyć projekcję; nie wolno zwrócić oryginału jako fallbacku.
- Symulacja kopiuje stan i generator RNG. Wcześniejszy, jawny kontrakt
  `shareable_simulation_snapshot?` pozostaje jedynym wyjątkiem; nie rozszerzamy
  go automatycznie na nowe gry.
- Kopia zachowuje symbole, Struct, cykle i aliasy wewnątrz grafu. Nie zamieniamy
  jej na JSON ani płytkie `dup`. `Replay#state` może być `nil`.
- Wewnętrzny `NinetyNinePlanning::State` posiada własny graf wartości,
  zamrożony po utworzeniu świata. Gałąź kopiuje kolekcje zmieniane przez
  reducer, a nowo wprowadzane wartości kart też są zamrożone. Ten jawny
  kontrakt planera nie zmienia kopii replayów ani ogólnego snapshotu.
- Cache aktywności należy do repository, po odczycie zaakceptowanych
  projekcji transportu. Porównuje pełne wartości, przechowuje własne kopie
  i oddaje nowe mutowalne wyniki. Współdzielenie wewnętrznych projekcji nie
  zastępuje walidacji ani bieżącej granicy wizyty widza.

`tools/benchmark-runtime.rb` mierzy oddzielnie replay, kopiowanie, budowę
specyfikacji, legalne ruchy, decyzję bota i koszt niezajętej blokady. Raport
zawiera wersję Ruby, platformę i SHA-256 korpusu. Nie porównuj czasu CPU
z RTT ani nie wyciągaj z niego wniosku o zachowaniu audio za natywnym oknem.
Przykład: `ruby tools/benchmark-runtime.rb --iterations 10 --output tmp/runtime.json`.
