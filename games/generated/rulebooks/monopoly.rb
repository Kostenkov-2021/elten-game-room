# Generated from tools/data/rulebooks/monopoly.json; run tools/compile-rulebooks.rb.
module GameRoomGames
  class Monopoly
    module GeneratedRulebook
      private

      def generated_rule_sections
        [
          rule_section(:journey, GameRoomRules.translate("A journey of buying and collecting rent"),
            GameRoomRules.translate("Two to eight players travel around the board, buy properties and charge visitors rent. Everyone starts with the cash assigned to the chosen board. Your aim is to remain solvent after all the others have gone bankrupt. Owning the most properties is useful, but is not itself a victory condition: you must still be able to meet your payments."),
            GameRoomRules.translate("On your turn, roll two dice and move by their sum. The field you reach determines what happens next: a purchase, rent, a tax, a card or another board instruction. The game moves to the next player once these decisions are settled; there is no separate End turn button. Doubles usually give you another roll, but three doubles in a row send you to jail without making the third move. Jail or a negative cash balance cancels an extra roll.")),
          rule_section(:ownership, GameRoomRules.translate("Buy a street, then complete its colour"),
            GameRoomRules.translate("An unowned street, station or utility may be bought when you land on it. The game gives its name, colour or type, and price. If you have enough cash, choose whether to buy. If you cannot afford it, the purchase is declined automatically. A property you do not buy remains available, unless the auction option sends it to auction."),
            GameRoomRules.translate("Streets belong to colour groups. Once you own every street in a group, you have a complete group: its undeveloped base rent doubles and you can start building there. For example, owning two out of three streets is still incomplete. The holdings lists show how many you own out of the whole group. Stations and utilities form their own sets, but never receive houses or hotels."),
            GameRoomRules.translate("Forbid buying properties on the first board round is off by default. If enabled, each player must first pass Start once before an unowned field offers them a purchase. This is your own first trip around the board, not the first circuit of turns taken by the table.")),
          rule_section(:auctions, GameRoomRules.translate("When a purchase becomes an auction"),
            GameRoomRules.translate("Put unsold properties up for auction is off by default. Turn it on if you want a declined purchase to be offered to the active players through bidding. Players take turns bidding or passing. Passing withdraws you from this auction. The remaining highest bidder pays their final bid and receives the property; the printed purchase price is not the amount automatically charged."),
            GameRoomRules.translate("Auction decision time is the number of seconds for one bid or pass. Zero, the default, gives unlimited time. A positive limit starts afresh for the next bidder after every accepted decision; exceeding it means an automatic pass. B lets you enter a total purchase bid, above the current bid and within your cash. Enter or G accepts the suggested next bid. You cannot save the game during an auction.")),
          rule_section(:rent, GameRoomRules.translate("Rent follows the deed"),
            GameRoomRules.translate("Landing on someone else's chargeable property makes you pay its owner. For a street, the amount depends on its rent schedule, colour group and buildings. Stations depend on how many stations the owner has. Utilities also use the dice total. A mortgaged property charges no rent. Open your holdings with V or another player's holdings with Shift+V, then press Enter on a property to check its current rent. For a utility, the description gives the multiplier of the visitor's dice total rather than using an earlier roll."),
            GameRoomRules.translate("Pay rents automatically is enabled by default. Without it, the owner decides whether to request or waive each eligible rent, and the visitor's move waits for this decision. Do not collect rent while in jail is a separate option, off by default. Enabling it removes rent income for an owner who is currently imprisoned; it does not remove their ownership.")),
          rule_section(:building, GameRoomRules.translate("Develop a group evenly"),
            GameRoomRules.translate("Manage your properties on your own turn before rolling, or while resolving your debt on that turn. To build, you need the complete colour group and no mortgages in that group. Add houses to the least developed streets first. In a three-street group you can reach one house on each before putting a second on any street. Four houses may be replaced by a hotel, the fifth development level."),
            GameRoomRules.translate("Selling reverses that process: remove buildings from the most developed streets and receive half their purchase price. The bank normally has 32 houses and 12 hotels on a 40-field board, or 48 houses and 18 hotels on a 60-field board. Turning a hotel back into four houses needs those houses to be available. If there are too few, the list explicitly offers selling all buildings in the colour group instead, still at half price."),
            GameRoomRules.translate("The building and selling lists show the colour, existing buildings and cost or proceeds. Confirm an operation with Enter and stay in the list to continue managing properties. If no operation is possible, the game explains why instead of making you select a building you cannot buy.")),
          rule_section(:mortgages, GameRoomRules.translate("Release cash without losing ownership"),
            GameRoomRules.translate("A mortgage pays you the property's mortgage value, while the property remains yours and stops earning rent. Before mortgaging a street, sell every building in its colour group. To remove the mortgage later, pay the mortgage amount plus 10%, rounded up to a whole money unit. For example, a mortgage of 100 costs 110 to clear. The lists display the actual payment before confirmation.")),
          rule_section(:trading, GameRoomRules.translate("Make an offer to another player"),
            GameRoomRules.translate("A trade may combine properties and cash from either side. E opens the players; Enter chooses a partner and announces that you are preparing an offer. It does not send an empty offer. In the form, enter the two cash amounts and choose properties from the two checkbox lists. Arrows move within a property list, while Tab moves between the form's sections. Send proposal submits the complete offer; Escape returns to the player list."),
            GameRoomRules.translate("Nothing changes hands until the recipient accepts. Both sides must still afford their payments and own the offered properties. Mortgaged properties and streets in a group with buildings cannot be traded. A bot may decline an apparently fair face-value purchase because the property completes or protects an important group; the printed price is not a promise that the owner will sell.")),
          rule_section(:debt, GameRoomRules.translate("When you owe more cash than you have"),
            GameRoomRules.translate("In Game Room, a negative balance ends your current turn. The other players take their turns before your next one begins. Then you can sell buildings, mortgage properties or arrange a trade to cover the shortfall. Roll remains the main action, but tells you how much is missing instead of rolling while the balance is negative. A payment charged outside your turn does not interrupt the current player's move."),
            GameRoomRules.translate("While in debt you may declare bankruptcy. It happens automatically on your own turn when you have no buildings left to sell and no property available to mortgage. A merely possible trade does not postpone this. If another player is your creditor, they receive your remaining properties and held jail cards, with buildings liquidated at half price. For a debt to the bank, the properties return to the bank. Bankruptcy ends your participation; the last player still solvent wins.")),
          rule_section(:jail, GameRoomRules.translate("Visiting jail is not being imprisoned"),
            GameRoomRules.translate("You are imprisoned only when a field, a card or three consecutive doubles sends you there. Simply stopping on the jail field is a visit. Before a prison roll, you may pay the exit fee or use a held jail card. Otherwise you have up to three turns to roll doubles. Successful doubles release you and move you by the roll, without an extra turn. After the third failed attempt, you pay and move by that roll."),
            GameRoomRules.translate("Lucky double one is off by default. If enabled, rolling two ones on a normal moving roll awards a quarter of the board's Start salary. The jail exit fee uses the same quarter-salary scale, rounded to whole money units.")),
          rule_section(:events, GameRoomRules.translate("Start, Free Parking and cards"),
            GameRoomRules.translate("Passing Start pays the board's salary. Double salary on Start, enabled by default, doubles that payment only when you land exactly on Start. Free parking jackpot is also on by default. Its pool starts at zero and collects eligible taxes and bank fees. Landing on Free Parking takes the whole pool and resets it to zero. Rent, trades, purchases, construction and mortgage transactions do not add to it. With the option off, Free Parking pays nothing."),
            GameRoomRules.translate("Chance and Community Chest use separate shuffled decks. A card may change money, move you, charge for buildings, send you to jail or give a retained jail-exit card. A retained card is unavailable in its deck until returned or used. Supplementary cards is enabled by default; turning it off removes the additional Game Room events, not the normal decks. Payments and destinations are adapted to the board you chose.")),
          rule_section(:boards, GameRoomRules.translate("Regional boards have their own figures"),
            GameRoomRules.translate("The default board is American / Atlantic City. A different board can change names, layout, currency, starting cash, Start salary and property economics. Larger boards also have more colour groups, stations and utilities. The profiles below are generated from the boards actually used by Game Room. Inspect individual deeds for purchase prices, rent levels and mortgage values."),
            GameRoomRules.translate("The Polish board is a custom Warsaw board. Regional data combines observed layouts and deed values with adapted salaries, fees, building costs and event cards; it is not a guarantee of matching every commercial or QC edition. In these profiles, Income Tax is one Start salary and Luxury Tax half a salary.")),
          board_profile_rules,
          rule_section(:controls, GameRoomRules.translate("Game keyboard shortcuts"),
            GameRoomRules.translate("Arrows: choose the current action or property."),
            GameRoomRules.translate("Enter: confirm the selected action."),
            GameRoomRules.translate("Escape: close the current list."),
            GameRoomRules.translate("I: read player positions and field numbers."),
            GameRoomRules.translate("T: read the turn and phase."),
            GameRoomRules.translate("C: read your cash."),
            GameRoomRules.translate("S: read player finances."),
            GameRoomRules.translate("F: read the current property's deed."),
            GameRoomRules.translate("D: browse unowned properties."),
            GameRoomRules.translate("Shift+D: browse the board."),
            GameRoomRules.translate("V: browse your properties."),
            GameRoomRules.translate("Shift+V: browse other players' properties."),
            GameRoomRules.translate("H: build houses or hotels."),
            GameRoomRules.translate("Shift+H: sell buildings."),
            GameRoomRules.translate("K: mortgage properties."),
            GameRoomRules.translate("Shift+K: unmortgage properties."),
            GameRoomRules.translate("E: prepare a trade."),
            GameRoomRules.translate("A: accept an incoming offer."),
            GameRoomRules.translate("R: reject an incoming offer."),
            GameRoomRules.translate("B: during an auction, enter your own total bid."),
            GameRoomRules.translate("G: during an auction, accept the suggested bid."),
            GameRoomRules.translate("Space: request rent when manual collection is available."),
            GameRoomRules.translate("P: pay to leave jail."),
            GameRoomRules.translate("J: use a get-out-of-jail card."))
        ]
      end
    end
    include GeneratedRulebook
  end
end
