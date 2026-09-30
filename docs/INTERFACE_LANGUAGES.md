# Independent interface languages

Game Room settings include a Language category after Axel Pong. Its fields are
Primary interface language, then Known languages (native multi-selection).
The primary language is always selected in Known languages. Language changes are
staged with the other settings: Save writes them, Cancel discards them. Restart
ELTEN to apply them to the entire program, including menus and the main-screen
widget. Merely closing the Game Room window does not reload its translated data.

The local `settings.json` stores language codes, not names or list indices:

```json
{"interface_language":"pl","known_languages":["en","pl"]}
```

For a new configuration, the primary language follows ELTEN when that language is
available in Game Room, otherwise English. Known-language defaults use the
already loaded `Session.languages` when available. There is no profile request or
write. Saving makes the choices explicit; subsequent ELTEN language/profile
changes do not overwrite them.

## Lookup and isolation

For each message, lookup tries the primary language, then the other selected
non-English languages in the order displayed in the list, then the original
English text. Selection order does not assign priority. Selecting English among
known languages does not stop lookup before another known translation. English
is complete source text, not a missing EN.mo catalog: selecting English as primary
always yields English.
Context and plural forms follow the same chain, using each catalog's plural rule.
An empty or unavailable translation is a miss, not a reason to hide the message.

`GameRoomLocalization` reads the settings and MO catalogs at startup. It never
changes `Configuration.language`, the account profile, or the host dictionary.
Translation calls do not read disk or account data. Each catalog has isolated
messages and a bounded, parsed plural expression; catalog headers are not Ruby
code and are never evaluated as such.

Production Ruby scopes use `GameRoomLocalization::Translations`, a lexical
refinement. Put `using` **inside** each root class/module that calls a translation
helper. A top-level `using` fails when the host evaluates source inside its loader
method. Each separately loaded file/reopened module needs its own declaration.
Top-level content registration calls the translator explicitly. The AST coverage
test detects unscoped translation helper calls in production files.

Host-provided controls can still announce their roles in ELTEN's language.
Recorded announcer audio is unchanged. Language choices do not change a table's
question/card/dictionary language, game options, content identity or other players'
interfaces. New computer names follow the local UI language where a matching
name pool exists; existing saved name tokens are not rewritten.

## Adding another interface translation

Supply an additional valid UTF-8 GNU MO catalog, such as `locale/CS.mo`, using the
same English message IDs, contexts and interpolation placeholders. Declare its
code in both program manifests' `supported_languages` and include it when packing.
There is no need for the host to have a Czech translation. Available choices come
from Game Room catalogs, plus source English. `X-Language-Name: Čeština` in the
catalog header supplies a native display name even when host language-name data
is absent. Invalid/missing catalogs are not offered as installed translations.

The current catalogs are Czech, Spanish, Polish and Russian, each with one
editable `locale/<LANG>.po` and one compiled `<LANG>.mo`. English uses source
messages. Historical JSON fragments and their exporter have been removed;
Polish rulebook documents are refreshed from the PO. Release notes live in
`lib/game_room_changelog.rb` and use the same PO/MO translation workflow.
See `docs/TRANSLATIONS.md` for editing, source updates and adding another language.

## Verification

Focused tests cover catalog selection, missing entries, contexts/plurals, startup
preference loading/caching, binary source scopes, settings focus/selection,
Save/Cancel, restart messaging, and the unchanged language/content of the host.
Real-host integration uses `ELTEN_HOST_SOURCE` and runs in an isolated Ruby
process, not in an active ELTEN session. Offline forms/loader checks are not a
claim of a live NVDA interaction test.
