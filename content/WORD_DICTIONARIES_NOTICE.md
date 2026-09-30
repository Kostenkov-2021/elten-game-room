# Scrabble word dictionaries

The game uses these local, versioned word lists, not OSPS, NWL, Collins or
Quentin's Playroom's dictionary. Game language is independent of UI language.

Polish: SJP.PL contributors, game dictionary dated 2026-09-01,
https://sjp.pl/sl/growy/sjp-20260901.zip (https://sjp.pl/sl/growy/).
Used under Creative Commons Attribution 4.0 International:
https://creativecommons.org/licenses/by/4.0/ . Source also offers GPL 2;
this distribution chooses CC BY 4.0. No endorsement by SJP.PL is implied.

English: Wordnik's open word list dated 2021-07-29, revision
46e6215d0f90356afe9c8ba4be347e7e98cb425c, https://github.com/wordnik/wordlist .
This is not the separately sold Wordnik Games Dataset. Some British forms
are absent (e.g. favourite). We do not invent or automatically add forms.

Changes made by ELTEN Game Room: UTF-8/NFC, lower case, removal of format
quotes, filtering to 2–15 letters of the language's tile alphabet,
deduplication, sorting and compressed block storage. No definitions or
word-finding suggestions. Original and transformed checksums are in pack
metadata; tools/build-scrabble-dictionaries.rb reproduces this transformation.
Structural checks are not an independent linguistic audit of every word.

## Wordnik license (preserved in full)

MIT License

Copyright (c) 2020 Wordnik

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
