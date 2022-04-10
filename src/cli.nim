import strutils
import terminal
import options
import parseutils

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
    stdout.write("   ")
  stdout.write("  │\n")
  stdout.write(" └───────┘ └───────┘\n\n")

  # ┌─ ♥ ─┐ ┌─ ♣ ─┐ ┌─ ♦ ─┐ ┌─ ♠ ─┐
  # │ AAA │ │ BBB │ │ CCC │ │ DDD │
  # └─────┘ └─────┘ └─────┘ └─────┘
  stdout.write("┌─ ♥ ─┐ ┌─ ♣ ─┐ ┌─ ♦ ─┐ ┌─ ♠ ─┐\n")
  for i in 0..3:
    let fou = storedData.foundation[i]

    stdout.write("│ ")
    if len(fou.cards) > 0:
      let (_, suit, value) = fou.cards[len(fou.cards)-1]
      let (text, color) = toStr(suit, value)
      stdout.styledWrite(color, bgWhite, text)
    else:
      stdout.write("   ")
    stdout.write(" │ ")
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

proc PlayTurn(storedData: var StoredData) =
  var hasInput = ""
  var err = ""
  var deck = none(DeckData)
  var cardId: ActorId

  var fromDeckType: ActorKind
  var fromDeckIndex: int

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

    stdout.write("INPUT: ")
    stdout.styledWrite(stockColor, "[S: cycle stock] ")
    stdout.styledWrite(talonColor, "[T: Use card from talon]")
    stdout.write(" [1-7: Take card from tableau]\n")

    if hasInput == "":
      deck = none(DeckData)
      var input = stdin.readLine().toLowerAscii()
      case input:
        of "s":
          if handWasteState == BothEmpty:
            err = "Stock is empty"
            continue

          DoCycleHand()
          UpdateDeck(storedData, GetDeckData(Hand, 0))
          UpdateDeck(storedData, GetDeckData(Waste, 0))
          break
        of "t":
          let cards = storedData.waste.cards
          if len(cards) == 0:
            err = "Talon is empty"
            continue

          let (id, suit, value) = cards[len(cards)-1]
          let (str, _) = toStr(suit, value)
          hasInput = "Talon: " & str
          cardId = id
          fromDeckType = Waste
          continue
        of "1", "2", "3", "4", "5", "6", "7":
          let index = int(input[0]) - int('0')
          let tableau = storedData.tableau[index-1]
          let cards = tableau.cards
          fromDeckType = tableau.kind
          fromDeckIndex = index

          if len(cards) == 0:
            err = "Tableau #" & $index & " is empty"
            continue

          if len(cards) == 1 or (cards[len(cards)-2][1] == None):
            let (id, suit, value) = cards[len(cards)-1]
            let (str, _) = toStr(suit, value)
            hasInput = "Tableau #" & $index & ": " & str
            cardId = id
            continue

          deck = some(tableau)
          hasInput = "Tableau #" & $index
          continue
        else:
          err = "Invalid input " & input
          continue
    stdout.writeLine(hasInput)

    if isSome(deck):
      let tableau = get(deck)

      var shownCards: seq[int]
      for i in countdown(len(tableau.cards)-1, 0):
        let (_, suit, value) = tableau.cards[i]
        if suit == None:
          continue
        shownCards.add(i)

        stdout.write("[" & $len(shownCards) & "]: ")
        let (text, color) = toStr(suit, value)
        stdout.styledWriteLine(color, bgWhite, text)

      let input = stdin.readLine().toLowerAscii()

      if input == "c":
        break

      var index: int
      try:
        let parsed = parseInt(input, index, 0)
        if parsed == 0:
          err = input & " is not a number"
          continue
      except:
        err = input & " has too many digits"
        continue

      if not (index in 1..len(shownCards)):
        err = $index & "is not between 1 and " & $len(shownCards)
        continue

      let (id, suit, value) = tableau.cards[shownCards[index-1]]
      if suit == None:
        err = "You can't play a hidden card"
        continue
      let (str, _) = toStr(suit, value)
      hasInput = "Tableau #" & $index & ": " & str
      cardId = id
      deck = none(DeckData)
      continue

    let moves = GetValidMovesForCard(cardId)
    stdout.write("Whereto?\n")
    for i, deckId in moves:
      let deck = GetDeckData(deckId)
      stdout.write("[" & $(i+1) & "]: " & $deck.kind & " #" & $deck.index & "\n")
    stdout.write("[c]: cancel\n")

    let input = stdin.readLine().toLowerAscii()
    if input == "c":
      break

    if len(moves) == 0:
      err = "Press c to cancel"
      continue

    var index: int
    try:
      let parsed = parseInt(input, index, 0)
      if parsed == 0:
        err = input & " is not a number"
        continue
    except:
      err = input & " has too many digits"
      continue

    if not (index in 1..len(moves)):
      err = $index & " is not between 1 and " & $len(moves)
      continue

    DoMove(cardId, moves[index-1])
    UpdateDeck(storedData, GetDeckData(moves[index-1]))
    UpdateDeck(storedData, GetDeckData(fromDeckType, fromDeckIndex))
    break


proc PlayLoop*() =
  var data = UpdateAll()
  while true:
    PlayTurn(data)
    # if all foundations have kings, game is won
    var filled = 0
    for i in 0..3:
      let foundation = data.foundation[i]
      if len(foundation.cards) == 13:
        filled += 1

    if filled == 4:
      stdout.writeLine("You won!")
      break