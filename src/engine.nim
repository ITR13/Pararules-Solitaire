import sequtils
import std/random
import std/algorithm

import pararules

randomize()

type
  ActorKind = enum
    Card, Tableau, Foundation, Hand, Waste

  CardSuit = enum
    None, Spades, Hearts, Diamonds, Clubs
  CardValue = 0..13 # Needs to allow 0 for decks, but cards can only be 1..13

  CardList = seq[ActorId]

  ActorId = 1..(52+7+4+1+1)

  Attr = enum
    Kind, Suit, Value,
    Hidden, Location, # Card specific
    Size, Cards, # Deck specific

  HandWasteState = enum
    BothEmpty, HandEmpty, HandNotEmpty,

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


let staticRules =
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

var session = initSession(Fact, autoFire=false)
for r in staticRules.fields:
  session.add(r)


proc CreateTableau(index: 1..7) =
  var actorId = ActorId(52+index)

  let rules =
    ruleset:
      rule updateDeck(Fact):
        what:
          (actorId, Cards, cards)
        then:
          let l = len(cards)
          session.insert(actorId, Size, l)
          if l == 0:
            session.insert(actorId, Suit, None)
            session.insert(actorId, Value, 0)
          else:
            let cardId = cards[l-1]
            let card = session.query(staticRules.getCard, id=cardId)
            session.insert(actorId, Suit, card.suit)
            session.insert(actorId, Value, card.value)

  for r in rules.fields:
    session.add(r)

  session.insert(actorId, Kind, Tableau)
  session.insert(actorId, Cards, @[])

proc CreateFoundation(index: 1..4) =
  var actorId = ActorId(52+7+index)

  let rules =
    ruleset:
      rule updateDeck(Fact):
        what:
          (actorId, Cards, cards)
        then:
          let l = len(cards)
          session.insert(actorId, Size, l)
          if l == 0:
            session.insert(actorId, Value, 0)
          else:
            let cardId = cards[l-1]
            let card = session.query(staticRules.getCard, id=cardId)
            session.insert(actorId, Value, card.value)

  for r in rules.fields:
    session.add(r)

  session.insert(actorId, Kind, Foundation)
  session.insert(actorId, Cards, @[])
  session.insert(actorId, Suit, CardSuit(index))

proc CreateHand() =
  var actorId = HAND_ID

  let rules =
    ruleset:
      rule updateDeckInfo(Fact):
        what:
          (actorId, Cards, cards)
        then:
          let l = len(cards)
          session.insert(actorId, Size, l)
          for i in 1..l:
            let cardId = cards[i]
            session.insert(cardId, Location, actorId)

  for r in rules.fields:
    session.add(r)

  session.insert(actorId, Kind, Hand)
  session.insert(actorId, Cards, @[])
  session.insert(actorId, Suit, None)
  session.insert(actorId, Value, 13) # No cards allowed

proc CreateWaste() =
  var actorId = WASTE_ID

  let rules =
    ruleset:
      rule updateDeck(Fact):
        what:
          (actorId, Cards, cards)
        then:
          let l = len(cards)
          session.insert(actorId, Size, l)

  for r in rules.fields:
    session.add(r)

  session.insert(actorId, Kind, Waste)
  session.insert(actorId, Cards, @[])
  session.insert(actorId, Suit, None)
  session.insert(actorId, Value, None)

proc CreateCard(suit: CardSuit, value: CardValue, deckActorId: ActorId) =
  if value == 0:
    raise newException(ValueError, "Cannot create card with value 0")

  let deck = session.query(staticRules.getDeck, id=deckActorId)

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
    for value in 1..13:
      cards.add((suit, CardValue(value)))

  shuffle(cards)

  # Left value is count, right is actorId
  let cardDistribution = @[
    (1, 1),
    (2, 2),
    (3, 3),
    (4, 4),
    (5, 5),
    (6, 6),
    (7, 7),
    (1000, HAND_ID) # Hand gets rest of cards
  ]

  for i, (suit, value) in cards:
    var dist = i
    for (count, actorId) in cardDistribution:
      if dist < count:
        CreateCard(suit, value, actorId+52)
        break
      else:
        dist -= count

  # Show top card of tableau and hand
  for tabId in 1..7:
    let deck = session.query(staticRules.getDeck, id=ActorId(52+tabId))
    # using len because size is not set yet since fireRules hasn't been called
    let cardId = deck.cards[len(deck.cards)-1]
    session.insert(cardId, Hidden, false)

  let hand = session.query(staticRules.getDeck, id=ActorId(HAND_ID))
  if len(hand.cards) > 0:
    let cardId = hand.cards[len(hand.cards)-1]
    session.insert(cardId, Hidden, false)

proc CreateAll() =
  CreateAllDecks()
  CreateAllCards()
  session.fireRules()
CreateAll()

func GetHandWasteState*(): HandWasteState =
  let hand = (
    {.cast(noSideEffect).}:
      session.query(staticRules.getDeck, id=HAND_ID)
  )
  let waste = (
    {.cast(noSideEffect).}:
      session.query(staticRules.getDeck, id=WASTE_ID)
  )

  if hand.size != 0:
    return HandNotEmpty
  if waste.size != 0:
    return HandEmpty
  return BothEmpty

func GetValidMovesForCard*(cardId: ActorId): seq[ActorId] =
  let card = (
    {.cast(noSideEffect).}:
      session.query(staticRules.getCard, id=cardId)
  )
  let deck = (
    {.cast(noSideEffect).}:
      session.query(staticRules.getDeck, id=card.location)
  )

  var validMoves: seq[ActorId]
  if card.hidden or deck.kind == Hand:
    return validMoves

  proc suitIsBlack(suit: CardSuit): bool =
    return case suit:
      of Spades: false
      of Hearts: false
      of Diamonds: true
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
    let tab = (
      {.cast(noSideEffect).}:
        session.query(staticRules.getDeck, id=tabId)
    )
    let acceptValue = (if tab.value == 0: 13 else: tab.value - 1)
    if isOppositeColor(card.suit, true) and card.value == acceptValue:
      validMoves.add(tabId)

  if isTopCardInDeck:
    # Cannot move multiple cards at once to the foundation
    for fouId in ActorId(52+8)..ActorId(52+12):
      # Foundation accepts cards of one more value (empty = 0) and of the same color
      let fou = (
        {.cast(noSideEffect).}:
          session.query(staticRules.getDeck, id=fouId)
      )
      let acceptValue = fou.value + 1
      if isOppositeColor(card.suit, false) and card.value == acceptValue:
        validMoves.add(fouId)

  return validMoves

func GetSelectableCards*(): seq[ActorId] =
  # You can select the top card of the waste and foundations
  # You can also select all shown cards in the tableau
  let waste = (
    {.cast(noSideEffect).}:
      session.query(staticRules.getDeck, id=WASTE_ID)
  )

  var selectable: seq[ActorId]

  if waste.size != 0:
    selectable.add(waste.cards[len(waste.cards)-1])

  for fouId in ActorId(52+8)..ActorId(52+12):
    let fou = (
      {.cast(noSideEffect).}:
        session.query(staticRules.getDeck, id=fouId)
    )
    if fou.size != 0:
      selectable.add(fou.cards[len(fou.cards)-1])

  for tabId in ActorId(52+1)..ActorId(52+7):
    let tab = (
      {.cast(noSideEffect).}:
        session.query(staticRules.getDeck, id=tabId)
    )
    for card in tab.cards:
      let hidden = (
        {.cast(noSideEffect).}:
          session.query(staticRules.getCard, id=card).hidden
      )
      if hidden:
        break
      selectable.add(card)

  return selectable

proc DoCycleHand*() =
  let state = GetHandWasteState()
  case state:
    of BothEmpty:
      raise newException(ValueError, "No cards in hand or waste")
    of HandEmpty:
      # Remove all cards from the waste, reverse, then add to hand
      let waste = session.query(staticRules.getDeck, id=WASTE_ID)
      var cards = reversed(waste.cards)

      session.insert(WASTE_ID, Cards, @[])
      session.insert(HAND_ID, Cards, cards)
    of HandNotEmpty:
      # Remove top card from hand and add to waste
      let hand = session.query(staticRules.getDeck, id=HAND_ID)
      let waste = session.query(staticRules.getDeck, id=WASTE_ID)
      let cardId = hand.cards[len(hand.cards)-1]
      let remainingCards = hand.cards[0..len(hand.cards)-2]

      session.insert(cardId, Hidden, false)
      session.insert(HAND_ID, Cards, remainingCards)
      session.insert(WASTE_ID, Cards, waste.cards & @[cardId])

  session.fireRules()

proc DoMove*(cardId: ActorId, toDeckId: ActorId) =
  # Note, this will mostly not check for valid moves
  # If you move a card from the waste or foundation, it will assume it's the top card
  let card = session.query(staticRules.getCard, id=cardId)
  let deck = session.query(staticRules.getDeck, id=card.location)
  let otherDeck = session.query(staticRules.getDeck, id=toDeckId)

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
