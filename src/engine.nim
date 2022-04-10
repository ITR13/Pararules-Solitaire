import sequtils
import std/algorithm
import std/random
import std/sets

import pararules

randomize()

type
  ActorKind* = enum
    Card, Tableau, Foundation, Hand, Waste,

  CardSuit* = enum
    None, Hearts, Clubs, Diamonds, Spades,
  CardValue* = 0..13 # Needs to allow 0 for decks, but cards can only be 1..13

  CardList = seq[ActorId]

  ActorId* = 1..(52+7+4+1+1)

  Attr = enum
    Kind, Suit, Value,
    Hidden, Location, # Card specific
    Size, Cards, # Deck specific

  HandWasteState* = enum
    BothEmpty, HandEmpty, HandNotEmpty,

  DeckData* = object
    kind*: ActorKind
    index*: int
    suit*: CardSuit
    cards*: seq[(ActorId, CardSuit, CardValue)]


schema Fact(ActorId, Attr):
  Kind: ActorKind

  Suit: CardSuit
  Value: CardValue
  Hidden: bool
  Location: ActorId

  Size: int
  Cards: CardList

const HAND_ID = ActorId(52+7+4+1)
const WASTE_ID = ActorId(52+7+4+1+1)


let rules =
  ruleset:
    rule getDeck(Fact):
      what:
        (id, Kind, kind)
        (id, Size, size)
        (id, Cards, cards)
        (id, Suit, suit)
        (id, Value, value)
    rule getCard(Fact):
      what:
        (id, Hidden, hidden)
        (id, Location, location)
        (id, Suit, suit)
        (id, Value, value)

let otherRules =
  ruleset:
    rule updateDeck(Fact):
      what:
        (id, Cards, cards)
        (id, Kind, kind, then = false)
      then:
        let l = len(cards)
        session.insert(id, Size, l)

        for cardId in cards:
          session.insert(cardId, Location, id)

        case kind:
          of Tableau:
            if l == 0:
              session.insert(id, Suit, None)
              session.insert(id, Value, CardValue(0))
            else:
              let cardId = cards[l-1]
              let card = session.query(rules.getCard, id=cardId)
              session.insert(id, Suit, card.suit)
              session.insert(id, Value, card.value)
          of Foundation:
            if l == 0:
              session.insert(id, Value, CardValue(0))
            else:
              let cardId = cards[l-1]
              let card = session.query(rules.getCard, id=cardId)
              session.insert(id, Value, card.value)
          of Hand, Waste:
            # Hand and Waste never change suit or value
            discard
          of Card:
            raise newException(ValueError, "Cards aren't decks")

var session = initSession(Fact, autoFire=false)
for r in rules.fields:
  session.add(r)
for r in otherRules.fields:
  session.add(r)


proc CreateTableau(index: 1..7) =
  var actorId = ActorId(52+index)

  session.insert(actorId, Kind, Tableau)
  session.insert(actorId, Cards, @[])

proc CreateFoundation(index: 1..4) =
  var actorId = ActorId(52+7+index)

  session.insert(actorId, Kind, Foundation)
  session.insert(actorId, Cards, @[])
  session.insert(actorId, Suit, CardSuit(index))

proc CreateHand() =
  var actorId = HAND_ID

  session.insert(actorId, Kind, Hand)
  session.insert(actorId, Cards, @[])
  session.insert(actorId, Suit, None)
  session.insert(actorId, Value, CardValue(0)) # Can't be placed onto

proc CreateWaste() =
  var actorId = WASTE_ID

  session.insert(actorId, Kind, Waste)
  session.insert(actorId, Cards, @[])
  session.insert(actorId, Suit, None)
  session.insert(actorId, Value, CardValue(0)) # Can't be placed onto

proc CreateCard(suit: CardSuit, value: CardValue, deckActorId: ActorId) =
  if value == 0:
    raise newException(ValueError, "Cannot create card with value 0")

  let deck = session.query(rules.getDeck, id=deckActorId)

  let actorId = ActorId(value + (
    case suit:
      of Spades: 13 * 0
      of Hearts: 13 * 1
      of Diamonds: 13 * 2
      of Clubs: 13 * 3
      of None: raise newException(ValueError, "Invalid suit")
  ))
  let hidden = (
    case deck.kind:
      of Card: raise newException(ValueError, "Cards are not decks")
      of Tableau: true
      of Foundation: false
      of Hand: true
      of Waste: false
  )

  session.insert(actorId, Kind, Card)
  session.insert(actorId, Suit, suit)
  session.insert(actorId, Value, value)

  session.insert(actorId, Hidden, hidden)
  session.insert(deckActorId, Cards, seq[ActorId](deck.cards) & @[actorId])

proc CreateAllDecks() =
  for i in 1..7:
    CreateTableau(i)
  for i in 1..4:
    CreateFoundation(i)
  CreateHand()
  CreateWaste()


proc CreateAllCards() =
  var cards: seq[(CardSuit, CardValue)]

  for suit in CardSuit:
    if suit == None:
      continue
    for value in 1..13:
      cards.add((suit, CardValue(value)))

  shuffle(cards)

  # Left value is count, right is actorId
  let cardDistribution = @[
    (1, 52+1),
    (2, 52+2),
    (3, 52+3),
    (4, 52+4),
    (5, 52+5),
    (6, 52+6),
    (7, 52+7),
    (1000, HAND_ID) # Hand gets rest of cards
  ]

  for i, (suit, value) in cards:
    var dist = i
    for (count, actorId) in cardDistribution:
      if dist < count:
        CreateCard(suit, value, actorId)
        break
      else:
        dist -= count

  # Show top card of tableau and hand
  for tabId in 1..7:
    let deck = session.query(rules.getDeck, id=ActorId(52+tabId))
    # using len because size is not set yet since fireRules hasn't been called
    let cardId = deck.cards[len(deck.cards)-1]
    session.insert(cardId, Hidden, false)

  let hand = session.query(rules.getDeck, id=ActorId(HAND_ID))
  if len(hand.cards) > 0:
    let cardId = hand.cards[len(hand.cards)-1]
    session.insert(cardId, Hidden, false)

proc CreateAll*() =
  CreateAllDecks()
  session.fireRules()
  CreateAllCards()
  session.fireRules()
CreateAll()

func GetHandWasteState*(): HandWasteState =
  {.cast(noSideEffect).}:
    let hand = session.query(rules.getDeck, id=HAND_ID)
    let waste = session.query(rules.getDeck, id=WASTE_ID)

  if hand.size != 0:
    return HandNotEmpty
  if waste.size != 0:
    return HandEmpty
  return BothEmpty

func GetValidMovesForCard*(cardId: ActorId): seq[ActorId] =
  {.cast(noSideEffect).}:
    let card = session.query(rules.getCard, id=cardId)
    let deck = session.query(rules.getDeck, id=card.location)

  var validMoves: seq[ActorId]
  if card.hidden or deck.kind == Hand:
    return validMoves

  proc suitIsBlack(suit: CardSuit): bool =
    return case suit:
      of Spades: true
      of Hearts: false
      of Diamonds: false
      of Clubs: true
      of None: raise newException(ValueError, "Invalid suit")

  let isBlack = suitIsBlack(card.suit)
  let isTopCardInDeck = deck.cards[len(deck.cards)-1] == cardId

  proc isOppositeColor(suit: CardSuit, ifNone: bool): bool =
    if(suit == None):
      return ifNone
    return suitIsBlack(suit) != isBlack

  for tabId in ActorId(52+1)..ActorId(52+7):
    # Tableau accepts cards of one less value (empty = 14) and of the opposite color
    {.cast(noSideEffect).}:
      let tab = session.query(rules.getDeck, id=tabId)

    let acceptValue = (if tab.value == 0: 13 else: tab.value - 1)
    if isOppositeColor(tab.suit, true) and card.value == acceptValue:
      validMoves.add(tabId)

  if isTopCardInDeck:
    # Cannot move multiple cards at once to the foundation
    for fouId in ActorId(52+8)..ActorId(52+12):
      # Foundation accepts cards of one more value (empty = 0) and of the same color
      {.cast(noSideEffect).}:
        let fou = session.query(rules.getDeck, id=fouId)

      let acceptValue = fou.value + 1
      if card.suit == fou.suit and card.value == acceptValue:
        validMoves.add(fouId)

  return validMoves

func GetSelectableCards*(): HashSet[ActorId] =
  # You can select the top card of the waste and foundations
  # You can also select all shown cards in the tableau
  {.cast(noSideEffect).}:
    let waste = session.query(rules.getDeck, id=WASTE_ID)

  var selectable: seq[ActorId]

  if waste.size != 0:
    selectable.add(waste.cards[len(waste.cards)-1])

  for fouId in ActorId(52+8)..ActorId(52+12):
    {.cast(noSideEffect).}:
      let fou = session.query(rules.getDeck, id=fouId)

    if fou.size != 0:
      selectable.add(fou.cards[len(fou.cards)-1])

  for tabId in ActorId(52+1)..ActorId(52+7):
    {.cast(noSideEffect).}:
      let tab = session.query(rules.getDeck, id=tabId)

    for card in tab.cards:
      {.cast(noSideEffect).}:
        let hidden = session.query(rules.getCard, id=card).hidden

      if hidden:
        break
      selectable.add(card)

  return toHashSet(selectable)

func GetDeckData*(deckId: ActorId): DeckData =
  {.cast(noSideEffect).}:
   let deck = session.query(rules.getDeck, id=deckId)

  var cardData: seq[(ActorId, CardSuit, CardValue)]

  for cardId in deck.cards:
    {.cast(noSideEffect).}:
      let card = session.query(rules.getCard, id=cardId)

    if card.hidden:
      cardData.add((deckId, None, CardValue(0)))
    else:
      cardData.add((cardId, card.suit, card.value))

  let deckIndex = (
    case deck.kind:
      of Tableau: (int(deckId) - 52)
      of Foundation: (int(deckId) - 52 - 7)
      of Hand: 0
      of Waste: 0
      of Card: raise newException(ValueError, "Invalid deck")
  )

  let deckData = DeckData(
    kind : deck.kind,
    index : deckIndex,
    suit : deck.suit,
    cards : cardData
  )

  return deckData

func GetDeckData*(kind: ActorKind, index: int): DeckData =
  # Note: Helper method, prefer GetDeckData if you have a deckId
  # Note: Index is 1-based and ignored for hand and waste
  let actorId = (
    case kind:
      of Tableau:
        (
          if index in 1..7:
            ActorId(52+index)
          else:
            raise newException(ValueError, "Invalid tableau index")
        )
      of Foundation:
        (
          if index in 1..4:
            ActorId(52+7+index)
          else:
            raise newException(ValueError, "Invalid foundation index")
        )
      of Hand: HAND_ID
      of Waste: WASTE_ID
      of Card: raise newException(ValueError, "Cards cannot be decks")
  )

  return GetDeckData(actorId)

proc DoCycleHand*() =
  let state = GetHandWasteState()
  case state:
    of BothEmpty:
      raise newException(ValueError, "No cards in hand or waste")
    of HandEmpty:
      # Remove all cards from the waste, reverse, then add to hand
      let waste = session.query(rules.getDeck, id=WASTE_ID)
      var cards = reversed(waste.cards)

      session.insert(WASTE_ID, Cards, @[])
      session.insert(HAND_ID, Cards, cards)
    of HandNotEmpty:
      # Remove top card from hand and add to waste
      let hand = session.query(rules.getDeck, id=HAND_ID)
      let waste = session.query(rules.getDeck, id=WASTE_ID)
      let cardId = hand.cards[len(hand.cards)-1]
      let remainingCards = hand.cards[0..len(hand.cards)-2]

      session.insert(cardId, Hidden, false)
      session.insert(HAND_ID, Cards, remainingCards)
      session.insert(WASTE_ID, Cards, waste.cards & @[cardId])

  session.fireRules()

proc DoMove*(cardId: ActorId, toDeckId: ActorId) =
  # Note: this will mostly *not* check for valid moves
  # If you move a card from the waste or foundation, it will assume it's the top card
  let card = session.query(rules.getCard, id=cardId)
  let deck = session.query(rules.getDeck, id=card.location)
  let otherDeck = session.query(rules.getDeck, id=toDeckId)

  case deck.kind:
    of Hand:
      raise newException(ValueError, "Cannot move from hand")
    of Card:
      raise newException(ValueError, "Card is not a deck")
    of Waste, Foundation:
      # Remove the card from the original deck and place it on top of the new one
      let remainingCards = deck.cards[0..len(deck.cards)-2]
      let otherDeckCards = otherDeck.cards & deck.cards[len(deck.cards)-1]

      session.insert(deck.id, Cards, remainingCards)
      session.insert(toDeckId, Cards, otherDeckCards)
    of Tableau:
      # Remove the card and all cards on top of it from the tableau
      let cardIndex = find(deck.cards, cardId)
      let remainingCards = deck.cards[0..cardIndex-1]
      let otherDeckCards = otherDeck.cards & deck.cards[cardIndex..len(deck.cards)-1]

      session.insert(deck.id, Cards, remainingCards)
      session.insert(otherDeck.id, Cards, otherDeckCards)

      # The top card of the tableau is always shown
      if len(remainingCards) > 0:
        session.insert(remainingCards[len(remainingCards)-1], Hidden, false)

  session.fireRules()
