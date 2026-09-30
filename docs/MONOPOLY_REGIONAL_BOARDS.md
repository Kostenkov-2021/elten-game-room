# Dane regionalnych plansz Monopoly

`content/monopoly_regional_data.rb` zawiera osobne profile osiemnastu edycji
QC: wszystkie 840 pól, oryginalne nazwy ulic, stacji i przedsiębiorstw,
kolory, gotówkę początkową, walutę oraz pojemność banku budynków.
`content/monopoly_boards.rb` składa z tych danych planszę. Polska jest nadal
własną 40-polową edycją Game Roomu, nie planszą pozyskaną z QC.

`games/monopoly.rb` korzysta z parametrów planszy przy rozpoczynaniu gry,
wypłacie za Start, czynszach, limitach budowania i kierowaniu do więzienia.
Kwoty stałych opłat i premii są proporcjonalne do wypłaty za Start; ceny,
czynsze, aukcje i wyceny nieruchomości respektują skalę waluty. Numery pól,
odległości i wyniki rzutów nie są skalowane.

## Obserwacje z klienta QC

Źródło: QuentinC Gameroom 2026.8.15, własne próbne partie z jednym botem.
Odczytano pełne układy wszystkich poniższych edycji, stan gotówki przed ruchem
i dostępny bank budynków. Ceny i czynsze podstawowe odczytano z 34 kart
nieruchomości na planszy dwunastu narodów. Dodatkowo odczytano pierwszą kartę
każdej z pozostałych edycji (w amerykańskiej drugą), a w Europie także ostatnią
ulicę, stację i przedsiębiorstwo. Współczynniki pozostałych kart regionalnych
są zastosowaniem wspólnej tabeli QC do odczytanego mnożnika waluty, nie osobnym
odczytem każdej karty na każdej planszy.

| Edycja | Pola | Gotówka początkowa | Skala kwot | Domy/hotele |
|---|---:|---:|---:|---:|
| Atlantic City | 40 | 1500 $ | 1 | 32/12 |
| Londyn | 40 | 1500 £ | 1 | 32/12 |
| Europa | 40 | 15000000 € | 10000 | 32/12 |
| Rzym | 40 | 1500 euro | 1 | 32/12 |
| Ameryka Łacińska | 60 | 9750 ¤ | 3 | 48/18 |
| Barcelona | 40 | 15000000 € | 10000 | 32/12 |
| Turcja | 40 | 1500 TL | 1 | 32/12 |
| Słowacja | 40 | 1500 € | 1 | 32/12 |
| Serbia | 40 | 15000000 RSD | 10000 | 32/12 |
| Czechy | 40 | 37500 CZK | 25 | 32/12 |
| Rosja | 40 | 1500 RUB | 1 | 32/12 |
| Ukraina | 40 | 1500 UAH | 1 | 32/12 |
| Rumunia | 60 | 35000000 RON | 10000 | 48/18 |
| Bałkany | 60 | 7000 ¤ | 2 | 48/18 |
| Indonezja | 60 | 35000000 Rupiah | 10000 | 48/18 |
| Azja Południowo-Wschodnia | 60 | 7000 ¤ | 2 | 48/18 |
| Indie | 40 | 1500 ₹ | 1 | 32/12 |
| Dwanaście narodów | 60 | 7000 ¤ | 2 | 48/18 |

Na dużej planszy jest 34 ulic w 12 grupach, 6 stacji i 4 przedsiębiorstwa.
Czynsze stacji w jednostkach podstawowych: 25, 50, 100, 200, 400, 600.
Mnożniki sumy kości dla przedsiębiorstw: 4, 10, 25, 50; także podlegają
przeliczeniu walutowemu.

Indonezja ma więzienie na polu 51, a nie 11. Pole odsyłające do więzienia jest
na pozycji 41. Ameryka Łacińska odsyła z pola 51 do 11. Pozostałe duże
plansze odsyłają z 41 do 11. Numeracja tej dokumentacji zaczyna się od 1;
indeksy stanu gry od 0.

## Nadal adaptacje, nie potwierdzone dane QC

Nie należy opisywać tych plansz jako kompletnych kopii QC jeden do jednego.
Publiczny opis formatu plansz na https://qcsalon.net/en/faq rozdziela mnożnik
waluty, kapitał, pensję i zapasy banku; samej pensji nie można wywnioskować
z cen nieruchomości z pewnością.

- Wypłatę za Start zaobserwowano dla Europy (2000000) i dwunastu narodów
  (500). Pozostałe profile przyjmują 200 razy skalę dla 40 pól, albo 250
  razy skalę dla 60 pól. `salary_observed: false` oznacza brak potwierdzenia
  z rozgrywki QC, a nie zweryfikowaną wartość regionalną.
- Dla pierwszych ośmiu kolorów zachowano dotychczasowe koszty domów
  50/50/100/100/150/150/200/200 razy skalę. Próbki QC potwierdzają sześć
  tych grup. Dodatkowe białe, brązowe i purpurowe przyjęto jako 250, 275
  i 400 razy skalę na podstawie pojedynczych odczytanych ulic. Jednolite
  koszty całego koloru nie zostały zweryfikowane osobno dla wszystkich ulic.
  Nieodczytany koszt szarej grupy wynika teraz z połowy ceny jej najtańszej
  ulicy (350 razy skalę), z równym kosztem budynków w całym kolorze. To
  uzasadnienie adaptacji, nie dodatkowa obserwacja QC.
- Stałe opłaty i premie odniesiono do pensji danej planszy: podatek dochodowy
  to jedna pensja, luksusowy połowa, więzienie i szczęśliwe jedynki ćwierć.
  Kwoty pieniężnych kart zachowują proporcje do klasycznej pensji 200.
  Rachunek jest całkowitoliczbowy, zaokrąglany do najbliższej jednostki,
  z połówkami w górę. Dla dwunastu narodów daje to podatki 500/250,
  więzienie/premię 125. Dla Indii nadal 200/100 i 50, z zachowaniem
  zaobserwowanego podatku 200. Nie mnożymy kwot jeszcze raz skalą waluty.
- Naprawy pierwszych ośmiu grup zachowują stawki podstawowe razy walutę.
  Dodatkowe budynki droższe od klasycznych 200 jednostek mają proporcjonalnie
  wyższe opłaty naprawy. Dom za 800 na planszy dwunastu narodów (próg 400)
  płaci dwukrotną stawkę. Ceny nieruchomości, czynsze i odczytane próbki
  budowania pozostały bez zmian.
- Zachowano liczbę i rodzaje kart oraz wariant jackpota Game Roomu. Cele
  kart dobiera układ planszy: najdroższa ulica, Start, ostatnia ulica środkowej
  grupy kolorów, pierwsza ulica za więzieniem i pierwsza stacja. Na planszy
  40-polowej zachowuje to dotychczasowe pola; na dużej obejmuje również
  dodatkowe kolory, a w Indonezji ulicę za więzieniem na polu 51.
- Rezerwa gotówkowa botów uwzględnia lokalną pensję i rzeczywiste czynsze.
  Wycena zakupu i handlu nadal wynika z rzeczywistych cen nieruchomości.
- Polska nie ma potwierdzonego odpowiednika na liście QC.

To jawnie wskazane ograniczenia zgodności z platformą odniesienia. Nie
ukrywać ich przy wydaniu. Do pełnej zgodności potrzeba dalszych odczytów
wynagrodzeń, kosztów budowania, opłat i talii.

Kontrakt danych i ich użycie sprawdza `test/games/monopoly/regional_test.rb`.
Nie jest to niezależne potwierdzenie wszystkich kwot w QC.
