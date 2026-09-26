# Doprecyzowanie pytań i czytelne zestawy TXT

Zmieniono 1638 pytań: 1109 w polskim zestawie ogólnym oraz 529
w Wiedźminie. Usunięto dodatkowo 10 pytań — po 5 z każdej bazy.
Wersja danych czterech polskich zestawów wzrosła z 5 do 6.
Nie zmieniono wersji programu, buildu ani angielskiej bazy pytań.

## Zakres

- Obywatelstwo, pochodzenie i poddaństwo: usunięto sformułowanie
  „obywatelstwo przypisano”, błędny rodzaj gramatyczny i niepasujące etykiety
  zawodów. Pytania uwzględniają posiadanie różnych obywatelstw w ciągu życia.
  W wybranych przypadkach historycznych doprecyzowano państwo, dynastię
  lub pochodzenie zamiast przypisywać współczesne obywatelstwo.
- Małżeństwa i mitologia: rozróżniono żonę, męża, partnera oraz kochanka.
  Przy wielu małżeństwach pytamy o jedną z wymienionych osób; tam, gdzie
  tradycje się różnią, wskazano konkretny utwór lub tradycję.
- Odkrycia: nazwano konkretne wyprawy, doświadczenia i wynalazki, odróżniając
  odkrycie od wyizolowania pierwiastka, demonstracji lub patentu.
- Wiedźmin: zastąpiono nieokreślone „powiązanie” relacją rodzinną,
  zawodową lub fabularną. Doprecyzowano warunkowe romanse, osoby o tych
  samych imionach, komiksy, filmy, antologie i gry fabularne. Skorygowano
  medium 24 zachowanych pytań, również rozróżnienie książek i ekranizacji
  we wspólnym podzestawie. Pełny zestaw i oba podzestawy korzystają nadal
  z jednej bazy.
- Dodatkowe błędne przesłanki: m.in. zabieg nazywany lekiem, współczesne
  wskazanie przypisane wycofanemu preparatowi oraz nieprawidłowe wskazania
  leków. Te wybrane przypadki zweryfikowano osobno w źródłach medycznych.
- Usunięto osierocone nawiasy po linkach wiki z dziewięciu odpowiedzi.

Nie jest to ponowny pełny audyt faktów wszystkich zestawów ani gwarancja,
że w pozostałych pytaniach nie ma błędów. Sprawdzono wskazane rodziny
nieprecyzyjnych sformułowań i dodatkowe znalezione przypadki. Korzystano
z zapisanych materiałów poprzedniego audytu, ponownie pobranych twierdzeń
Wikidanych oraz dodatkowych źródeł. Nie wszystkie strony Wiedźmin Wiki
pobierano od nowa. Same testy techniczne nie potwierdzają prawdziwości faktów.

## Usunięte pytania

- Obywatelstwo Telesfora, Euklidesa i Rafaela Santiego — wskazanej
  odpowiedzi nie udało się rzetelnie potwierdzić; nie zastępowano jej domysłem.
- Małżonka Baala — pytanie mieszało tradycje i traktowało niepewną relację
  jako jednoznaczne małżeństwo.
- Terapia konwersyjna jako leczenie choroby — fałszywa przesłanka;
  homoseksualność nie jest chorobą.
- Ojcostwo Sambuka wobec Abrada Starego Dębu — źródło oznacza je jako
  przypuszczenie, nie ustalony fakt.
- Cztery pytania o relację Raffarda Białego i Lylianny — informacja
  pochodzi z wypowiedzi twórcy, a nie z ukończonej gry. Nie spełnia warunku
  faktu dostępnego w samym medium, którego dotyczy zestaw.

## Zestawy do czytania

W katalogu `docs/quiz-questions/` są kompletne, generowane pliki TXT:

| Zestaw | Pytań |
| --- | ---: |
| Wiedza ogólna — polski | 11083 |
| General knowledge — English | 13903 |
| Wiedźmin — pełny | 5132 |
| Wiedźmin — gry | 2668 |
| Wiedźmin — książki i ekranizacje | 2464 |

Każdy wpis zawiera pytanie, odpowiedzi A–D i poprawną odpowiedź, bez
identyfikatora. Wystarczy zgłaszać nazwę zestawu i treść pytania.
Angielski zestaw wyeksportowano bez zmian treści. Listy nie są zasobem
wykonawczym gry i nie są pakowane do instalatora.

Zasada w `AGENTS.md` wymaga odtworzenia TXT po każdej zmianie bazy.
Eksporter `tools/export-quiz-text.rb` ma tryb `--check`, a test
`test/quiz_text_export_test.rb` sprawdza kompletność, odpowiedzi, brak ID
i zgodność plików z bazą. Wewnętrzny raport
`QUIZ_SEMANTIC_CORRECTIONS_239.json` zachowuje techniczne identyfikatory,
treści przed i po zmianie, uzasadnienia oraz źródła; nie jest listą dla graczy.
