# Rosyjski interfejs i quiz

PR #25 autorstwa Danila (Kostenkov-2021) dodaje rosyjski interfejs oraz
36 pytań wiedzy ogólnej. Język interfejsu wybiera się w ustawieniach ogólnych,
a język treści quizu oddzielnie, przy tworzeniu stołu.

Teksty autora zachowano w `locale/RU.po`. Nie są oznaczone jako `fuzzy`.
Nieprzetłumaczone nowe komunikaty korzystają z angielskiego tekstu źródłowego.
Konteksty i odmiana liczby muszą pozostać częścią tożsamości komunikatu:
`queen` oznacza damę karcianą, a `queen` w kontekście `chess` — hetmana.

Po zmianach źródeł lub katalogu, z katalogu repozytorium:

```console
ruby tools/translations.rb update
ruby tools/translations.rb compile
ruby tools/translations.rb check
ruby tools/run-tests.rb test/russian_translation_test.rb test/quiz_russian_content_test.rb test/quiz_text_export_test.rb
```

Narzędzia tłumaczeń wymagają zależności z `tools/Gemfile.i18n`.
Testy używają wspólnego parsera PO i rzeczywistej lokalizacji programu,
uwzględniając kontekst oraz rosyjskie formy liczby mnogiej.

Po zmianie pytań należy uruchomić `ruby tools/export-quiz-text.rb`.
Plik `docs/quiz-questions/obshchie-znaniya-ru.txt` zachowuje wspólny format:
kolejny numer, pytanie, odpowiedzi A–D i prawidłowa odpowiedź.
Eksport do przeglądania nie jest częścią instalatora.
