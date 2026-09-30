# Interface translations

Edit one standard Gettext PO per language. The `locale/` directory contains:

- `CS.po`, `ES.po`, `PL.po`, `RU.po`: editable Czech, Spanish, Polish and Russian catalogs.
- `<LANG>.mo`: the four compiled runtime catalogs.
- `game-room.pot`: the generated English-message template.

English uses source messages and needs no `EN.po` or `EN.mo`. Keep the flat
`locale/<LANG>.mo` paths: both ELTEN builders encode these files as language
records with two-letter codes, and the source runtime reads the same paths.
The release staging list includes only MO files from this directory.

The catalogs contain interface labels, announcements, rules/help and the
in-app changelog. Scrabble/Krowa dictionaries, quiz questions, Taboo cards,
game IDs, board data and recordings remain separate gameplay resources.

## Editing and compiling

Use Ruby 4.0 and install the build-time dependencies once:

```console
bundle install --gemfile tools/Gemfile.i18n
```

Edit `msgstr` in Poedit or another Gettext editor. Preserve English `msgid`,
contexts, `%{name}` placeholders and plural variants. Empty translations use
the existing fallback; fuzzy and obsolete entries are not compiled.

After changing English messages or rulebook structure:

```console
ruby tools/compile-rulebooks.rb
ruby tools/translations.rb update
```

`update` refreshes references, adds empty entries and writes the POT while
preserving existing translations. It does not delete historical or dynamic
messages merely because static extraction cannot find them.

After editing a PO:

```console
ruby tools/translations.rb compile PL
ruby tools/translations.rb check PL
```

Compilation writes MO and refreshes Polish text in `tools/data/rulebooks/*.json`.
Release notes come from `lib/game_room_changelog.rb` and their PO/MO translations;
no separate Markdown copy is generated. The English structure stays authoritative;
edit Polish wording in `PL.po`. `check` is read-only and fails on stale output.
Omitting the language processes every PO. Neither command edits PO or POT.

The former locale JSON fragments, context sidecar and compatibility manifest
have been removed. Commands do not recreate them. Existing wording regressions
use one independent reference fixture under `test/fixtures/`, never an exporter
that copies the current translation into its own expected result.

## Adding a language

```console
ruby tools/translations.rb new DE --name "Deutsch"
ruby tools/translations.rb compile DE
ruby tools/translations.rb check DE
```

`new` creates only a PO and refuses to overwrite one. Translate the draft
before compiling it; declare the new language in both `manifest.json` and
the embedded manifest in `__app.rb` when it is ready to ship. A translation
does not require that language in the host. The checked-in plural defaults
are in `tools/plural_forms.json`; an unsupported language can provide explicit
`--plural-forms`. No CLDR download or runtime Gettext dependency is needed.

`import-mo LANG` is an explicit recovery operation for a missing PO. It reads
the complete MO, preserving contexts and plural forms, and refuses to overwrite
an existing PO. Ordinary compilation reads only PO.

## Build compatibility

```console
ruby test/run.rb test/tooling/locale_build_contract_test.rb
```

Set `ELTEN_HOST_SOURCE` to the pinned ELTEN 3.0.4 checkout described in
[BUILDING.md](BUILDING.md). The test runs its unmodified
`build-eltenapp.rb` and `build-eltsetup.rb` on a disposable fixture, reads both
with the native loader and compares every MO byte and language ID. It also
checks manifest/staging agreement, English fallback and absence of PO/POT
from the package. It does not build a Game Room release, sign or install one.
