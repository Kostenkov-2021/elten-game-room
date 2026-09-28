# Pytania do przeglądania poza grą

Każdy plik TXT odpowiada jednemu zestawowi dostępnemu w quizie. Zawiera
numer w osobnej linijce przed pytaniem, pytanie, cztery odpowiedzi A–D
i poprawną odpowiedź. Numeracja zaczyna się od 1 w każdym pliku i dotyczy
bieżącej kolejności pytań, nie ich technicznych identyfikatorów. Aby zgłosić
błąd, wystarczy podać nazwę zestawu i treść pytania. Pełny Wiedźmin zawiera
również pytania z obu zestawów szczegółowych.

Rosyjski zestaw wiedzy ogólnej znajduje się w `obshchie-znaniya-ru.txt`.

To generowane kopie do redakcji, nie druga baza gry. Poprawki wprowadza się
w źródłowej bazie `content/`, następnie odtwarza listy:

    ruby tools/export-quiz-text.rb

Kontrola aktualności, bez zapisywania:

    ruby tools/export-quiz-text.rb --check

Kolejność odpowiedzi w TXT jest stała, ale może być inna niż podczas partii.
Eksport nie zmienia pytań, losowania ani stanu gry. Pliki są w UTF-8.
Materiały te nie trafiają do instalatora. Pochodzenie i licencje treści
pozostają takie same jak dla odpowiednich zestawów w `content/`.
