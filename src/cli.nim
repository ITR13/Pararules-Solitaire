import strutils
import terminal
import options

import engine

type
  StoredData = object
    hand: DeckData
    waste: DeckData
    tableau: array[7, DeckData]
    foundation: array[4, DeckData]
    stock: DeckData

const suitSymbols = [
  " ", #Hearts, Clubs, Diamonds, Spades,
  "♥",
  "♣",
  "♦",
  "♠",
]

const rankSymbols = [
  "",
  "A",
  "2",
  "3",
  "4",
  "5",
  "6",
  "7",
  "8",
  "9",
  "10",
  "J",
  "Q",
  "K",
]

func toStr(suit: CardSuit, value: CardValue): (string, ForegroundColor) =
  let suitSymbol = suitSymbols[int(suit)]
  let rankSymbol = rankSymbols[int(value)]
  let color = (
    case suit:
      of Spades, Clubs: fgBlack
      of Hearts, Diamonds: fgRed
      of None: fgWhite
  )

  return (center("Z" & rankSymbol, 3).replace("Z", suitSymbol), color)

proc UpdateDeck(storedData: var StoredData, deckData: DeckData) =
  case deckData.kind:
    of Card:
      raise newException(ValueError, "Cards aren't decks")
    of Hand:
      storedData.hand = deckData
    of Waste:
      storedData.waste = deckData
    of Foundation:
      storedData.foundation[deckData.index - 1] = deckData
    of Tableau:
      storedData.tableau[deckData.index - 1] = deckData

func UpdateAll(): StoredData =
  StoredData(
    hand: GetDeckData(Hand, 0),
    waste: GetDeckData(Waste, 0),
    tableau: [
      GetDeckData(Tableau, 1),
      GetDeckData(Tableau, 2),
      GetDeckData(Tableau, 3),
      GetDeckData(Tableau, 4),
      GetDeckData(Tableau, 5),
      GetDeckData(Tableau, 6),
      GetDeckData(Tableau, 7),
    ],
    foundation: [
      GetDeckData(Foundation, 1),
      GetDeckData(Foundation, 2),
      GetDeckData(Foundation, 3),
      GetDeckData(Foundation, 4),
    ],
  )

proc PrintGame(storedData: StoredData) =
  stdout.eraseScreen()
  stdout.write("\n")

  let stockCount = len(storedData.hand.cards)
  let stockCountStr = center($stockCount, 5)
  let talon = storedData.waste



  # ┌ STOCK ┐ ┌ TALON ┐
  # │ AAAAA │ │  BBB  │
  # └───────┘ └───────┘
  stdout.write(" ┌ STOCK ┐ ┌ TALON ┐\n")
  stdout.write(" │ ")
  stdout.write(stockCountStr)
  stdout.write(" │ │  ")
  if len(talon.cards) > 0:
    let tc = talon.cards
    let (_, suit, value) = tc[len(tc)-1]
    let (text, color) = toStr(suit, value)

    stdout.styledWrite(color, bgWhite, text)
  else:
    stdout.write("  ")
  stdout.write("  │\n")
  stdout.write(" └───────┘ └───────┘\n\n")

  # ┌─ ♥ ─┐ ┌─ ♣ ─┐ ┌─ ♦ ─┐ ┌─ ♠ ─┐
  # │ AAA │ │ BBB │ │ CCC │ │ DDD │
  # └─────┘ └─────┘ └─────┘ └─────┘
  stdout.write("┌─ ♥ ─┐ ┌─ ♣ ─┐ ┌─ ♦ ─┐ ┌─ ♠ ─┐\n")
  for i in 0..3:
    let fou = storedData.foundation[i]

    stdout.write("| ")
    if len(fou.cards) > 0:
      let (_, suit, value) = fou.cards[len(fou.cards)-1]
      let (text, color) = toStr(suit, value)
      stdout.styledWrite(color, bgWhite, text)
    else:
      stdout.write("   ")
    stdout.write(" | ")
  stdout.write("\n")
  stdout.write("└─────┘ └─────┘ └─────┘ └─────┘\n")

  # ┌─ TABLEAU ───────────────────┐
  # │ [1] [2] [3] [4] [5] [6] [7] │
  # | AAA BBB CCC DDD EEE FFF GGG | x 19
  # └─────────────────────────────┘

  stdout.write("┌─ TABLEAU ───────────────────┐\n")
  stdout.write("│ [1] [2] [3] [4] [5] [6] [7] │\n")
  for i in 1..19:
    stdout.write("│ ")
    for index in 0..6:
      let tableau = storedData.tableau[index]
      let cardIndex = i - 1

      if cardIndex < len(tableau.cards):
        let (_, suit, value) = tableau.cards[cardIndex]
        let (text, color) = toStr(suit, value)
        stdout.styledWrite(color, bgWhite, text)
      else:
        stdout.write("   ")
      stdout.write(" ")
    stdout.write("│\n")

  stdout.write("└─────────────────────────────┘\n")
  stdout.write("\n")

proc PlayTurn(storedData: var StoredData) =
  var hasInput = ""
  var err = ""
  var deck = none(DeckData)
  var cardId: ActorId

  while true:
    PrintGame(storedData)

    if err != "":
      stdout.styledWriteLine(fgRed, err)
      err = ""
    else:
      stdout.writeLine("")

    # Read what the user wants to do
    let handWasteState = GetHandWasteState()
    let stockColor = (if handWasteState == BothEmpty: styleDim else: styleBright)
    let talonColor = (if len(storedData.waste.cards) == 0: styleDim else: styleBright)

    stdout.write("\nINPUT: ")
    stdout.styledWrite(stockColor, "[S: cycle stock] ")
    stdout.styledWrite(talonColor, "[T: Use card from talon]")
    stdout.write(" [T1-7: Take card from tableau]\n")

    if hasInput == "":
      deck = none(DeckData)
      var input = stdin.readLine()
      case input:
        of "S":
          if handWasteState == BothEmpty:
            err = "Stock is empty"
            continue

          DoCycleHand()
          UpdateDeck(storedData, GetDeckData(Hand, 0))
          UpdateDeck(storedData, GetDeckData(Waste, 0))
          break
        of "T":
          let cards = storedData.waste.cards
          if len(cards) == 0:
            err = "Talon is empty"
            continue

          let (id, suit, value) = cards[len(cards)-1]
          let (str, _) = toStr(suit, value)
          hasInput = "Talon: " & str
          cardId = id
          continue
        of "T1", "T2", "T3", "T4", "T5", "T6", "T7":
          let index = int(input[1]) - int('0')
          let tableau = storedData.tableau[index-1]
          let cards = tableau.cards
          if len(cards) == 0:
            err = "Tableau #" & $index & " is empty"
            continue

          deck = some(tableau)
          hasInput = "Tableau" & $index
          continue
        else:
          err = "Invalid input " & input
          continue
    stdout.writeLine(hasInput)


proc PlayLoop*() =
  var data = UpdateAll()
  while true:
    PlayTurn(data)
    if len(data.waste.cards) == 0:
      break
