# Digipoly — Project Context

> Read this file to get full context about the app: the idea, the rules it
> implements, how it's built, and the decisions behind it. It reflects the
> actual code; update it when architecture or rules change.

## What it is

Digital banking for **physical** Monopoly-style board games. Players keep the
real board, tokens and cards on the table, but all money lives in the app —
like a real mobile banking app (the UI deliberately imitates fintech apps:
gradient balance card, send/request flows, activity feed, payment cards, QR).

Everything runs on the **local network only**: no accounts, no internet, no
central server. Game nights often have no internet — nothing may depend on it
(this is why runtime-fetched Google Fonts were removed: their per-weight
loads re-layout the app and fail offline).

The app is board-agnostic: a **Board** is plain JSON data (currency symbol,
starting balance, GO salary, properties with rent tiers, Chance/Community
Chest card decks). It was built and tested against a custom, non-Classic
board — boards with different names/currencies/properties must all work.

## Core architecture (server-authoritative)

- One device **hosts** a room: it runs `GameServer` (shelf + shelf_web_socket)
  and is the single source of truth. It validates every intent via
  `GameEngine`, persists, then **broadcasts events to everyone — including
  the sender**. Clients never write state locally first.
- The host device participates through a normal `GameClient` pointed at
  `127.0.0.1` — one code path for host and guests.
- On (re)connect the server sends a full **snapshot** (game+board, players,
  transactions, ownerships, current turn, last dice roll) and the client
  replaces its local copy wholesale.
- **Identity ≠ connection**: each device has a permanent UUID
  (`IdentityService`, shared_preferences). Sockets can die and reconnect;
  the seat and balance survive. "Leave game" is an explicit action.
- Server pings every 5s (`webSocketHandler(pingInterval:)`) so force-closed
  phones are detected and marked offline.
- Clients auto-reconnect (4s timer) while a session is resumable.
- Rooms are advertised via mDNS (`bonsoir`, `_digipoly._tcp`), with manual
  IP entry as fallback. Port is always tried at **47912** first
  (`GameServer.defaultPort`); the room-info sheet shows the IP big and the
  full join link small, and copying copies the **link**.

## Game rules implemented

- **Turn flow (user-chosen rule)**: a turn is *housekeep → roll → resolve
  the landing → end*. Two gates in `GameProvider`:
  - `canAct` (my turn, **before** the roll): building/selling houses only.
  - `canResolve` (my turn, before **or** after the roll): every money move
    — free-form sends, collecting from the bank — and landing effects:
    buying the square you're on, paying its rent, Chance/Community Chest,
    Pass GO. Post-roll sends matter because taxes and card effects ("pay
    each player…") are settled via Send after landing.
  "End turn" stays disabled until you rolled (enforced server-side too).
  Exceptions: **requesting money, answering a money request, and paying via
  a scanned payment QR are allowed anytime** (like showing a Receive code)
  — scanning someone's QR is the same "you're being asked to pay" situation
  as a request, just without the formal accept/decline round trip
  (`SendMoneyScreen.fromScannedCode`).
- **Dice are server-side**: one roll per turn, only by the current player
  (`rollDice`/`diceRolled`), same result on every device, shown on the
  balance-card turn chip, dice sheet and dashboard. **Doubles roll again**:
  a double leaves the turn un-rolled server-side, so the player gets (and,
  since ending requires a roll, must take) another throw — unless that
  double's move sends them to jail, which cancels the bonus roll. **Three
  doubles in a row** sends the player straight to jail instead — no move,
  no GO salary, no landing effect on that 3rd roll, and the turn ends there
  (`GameServer._consecutiveDoubles`, in-memory only, reset whenever the
  turn changes — a host restart mid-streak loses the count, same tradeoff
  as the in-memory-only auction state). Only meaningful on a board with a
  curated layout (no position tracking, no rule, otherwise).
- **Board layout & token positions (optional per board)**: `Property` gained
  non-ownable kinds — `go`, `jail`, `freeParking`, `goToJail`, `tax`, `chance`,
  `communityChest` — living in the *same* `Board.properties` list as
  ownable ones; **list order is the board's physical square order**, set by
  dragging in the board editor. A board with no `go` square
  (`Board.goIndex == -1`) has no curated layout and the app behaves exactly
  as it always has — fully manual, no position tracking. Once a board has
  one, every roll auto-advances the roller's `Player.position`
  (`GameEngine.advancePosition`) and resolves the landing square server-side:
  - Passing/landing on GO auto-pays salary (doubled if landed on exactly) —
    the manual "Pass GO" quick action is hidden once a board has a layout.
  - Landing on Tax auto-charges the bank (`Property.price` reused as the
    tax amount) and feeds the **Free Parking pot**; landing on Free Parking
    pays the pot out and resets it to 0 (a house rule, not official
    Monopoly, added because the user wanted it). **Only the two Tax
    squares feed the pot** — a jail fine and a Chance/Community Chest money
    penalty (including a building-repairs card) are paid straight to the
    bank, same as official rules, and never touch the pot. This is a
    deliberate, narrower scope than some versions of the house rule (which
    often throw jail fines and card penalties in too) — matches how the
    user has always actually played it.
  - Landing on Go To Jail teleports to `Board.jailIndex`, sets `inJail`.
  - Landing on Chance/Community Chest auto-draws a card (same server logic
    as the manual quick action, just triggered by the landing).
  - Buying, paying rent, and mortgaging stay fully manual/confirmed, as
    always — only the *detection* of what square you're on is new.
- **Jail** (only reachable via a Go To Jail square, or a "go to X" card
  targeting either the Go To Jail or the plain Jail square — see below): on
  your turn, use a held
  Get Out of Jail Free card (`Player.jailCards`, free — see Chance/Community
  Chest below), pay `Board.jailFine` anytime before rolling to leave
  immediately, or roll — doubles escape free and move that roll,
  non-doubles add a failed attempt (`Player.jailTurns`), and the 3rd failed
  attempt forces paying the fine (still moving that roll).
- **Properties**: buy (list price), build houses 0–4 + hotel (=5). A plain
  buy is only valid for the square your own token is actually on (checked
  both client- and server-side via `GameEngine.validatePurchase`'s position
  check) — boards with no curated layout track no position, so the
  restriction doesn't apply there. Paying rent gets the same treatment:
  the payer must actually be standing on that square (`_handlePayRent`
  checks `payer.position`, not just who owns the property — same
  no-curated-layout exemption), so a player can't browse to some other
  property owned by the same opponent and pay rent on it from across the
  board; miss the moment (nobody asks, the payer doesn't pay) and it's
  gone until they land there again, same as real Monopoly. Building
  requires owning the **whole color group** and follows the **even-building
  rule**: no street of the group may end up more than one house apart from
  another — building spreads across the group, selling comes off the
  tallest first (hotel counts as 5). Hotel only via 4 houses (stepper is
  ±1). Sell-back refunds half. Rent auto-computed: street tiers, double
  base rent on a full unbuilt group, railroads by count owned, utilities =
  multiplier × dice (uses the payer's own in-app roll automatically).
- **Live auctions**: mirrors the official rule exactly — the only way one
  starts is the player standing on an unowned square, on their own turn,
  declining to buy it (**"Decline — start an auction"** on the property
  sheet). There's no free-form "auction any property, anytime" path; an
  earlier version had one, but it let a player force a sale on a square
  they had no actual claim to, with no basis in the rules. Both the turn
  and the position are enforced server-side too (`_handleStartAuction`) —
  boards with no curated layout track no position at all, so only the turn
  check applies there, same exemption `GameEngine.validatePurchase` already
  makes for a plain buy. Only one auction runs at a time table-wide —
  starting a second while one is already running is rejected server-side,
  and the client disables "Decline — start an auction" (with an
  explanatory label swap) whenever `GameProvider.auctions` isn't empty, so
  the rejection round-trip is the rare case rather than the norm. Everyone
  connected sees a shared live `AuctionCard` (game screen, dashboard, and
  the property sheet) with the current bid and who's leading; anyone can
  raise it anytime, no turn order, as long as it beats the current bid and
  they can afford it; anyone can close it, selling to the top bidder at
  their bid (skips the "must be standing on it" check, same as any
  explicit-price buy) or cancelling if nobody bid — **except the leading
  bidder themselves**, who the server refuses to let close their own
  auction (a confirmation dialog on the client, plus a hard server-side
  check): with no guard, anyone could start an auction, bid low once, and
  immediately sell it to themselves before anyone else had a chance to
  bid. Someone else at the table has to close it (cancelling with no bids
  at all is still open to anyone, including the starter). State lives
  server-side only (`GameServer._auctions`, `PropertyAuction` model) — not
  persisted to the DB, but replayed to (re)connecting clients via the
  snapshot, so a table restart or reconnect doesn't need to restart
  mid-auction. Wire: `startAuction`/`placeBid`/`closeAuction` intents,
  `auctionStarted`/`auctionBid`/`auctionClosed`/`auctionRejected` events.
- **Trades (property transfer)**: the owner hands a deed to another player
  from the property sheet ("Transfer to another player" → pick → confirm).
  No money moves — the deal's cash is a normal Send; buildings on the
  property itself must be sold first. Giving it away also breaks the
  sender's monopoly on the rest of that color group, and building requires
  owning the whole group in *both* directions (even selling — see
  Properties above), so any houses still standing on the sender's other
  streets in that same group must come down too, or they'd be stuck
  unsellable once the group splits. A mortgage travels with the property.
  Not turn-gated (trades happen anytime at the table). Wire:
  `transferProperty` intent; the
  `propertyChanged` broadcast carries the intent's `txId` so the sender's
  pending future resolves, alongside a $0 `TransactionType.transfer`
  logged in the activity feed (the only transaction type that never moves
  money — it exists purely as a record of who got what). The recipient
  also gets a "Property received" popup wherever they're looking.
- **Mortgages**: the owner mortgages a property from its sheet — the bank
  pays `mortgageValue`; while mortgaged no rent is due (computeRent
  rejects, visitors see a "Mortgaged" note, list shows a badge), streets
  need the whole group building-free to mortgage and unmortgaged to build.
  Lifting costs value + 10% interest (`GameEngine.mortgageLiftCost`).
  Allowed the whole turn (`canResolve`, like other bank moves).
- **Money requests**: requester → server → target sees an approval dialog
  anywhere in the app; accepting sends a normal validated payment carrying
  the requestId. Server rejects upfront if target can't afford it; auto-
  declines (notifying both sides) if the accepted payment fails; requester
  backing out **withdraws** the request. Both sides' UI auto-dismisses.
- **Kick / Replace**: host-only moderation, from a player's long-press
  sheet. Kicking marks them `hasLeft` — same effect as leaving voluntarily,
  balance and properties frozen exactly as they were, no liquidation
  (`_handleKickPlayer`/`_removePlayer`, shared with `leaveGame`'s own code
  path; the kicked device gets a dedicated `kicked` event before its
  connection closes, since unlike a self-leave it didn't already know).
  Replacing shares a join link/QR tagged with the vacant seat's id
  (`?claim=<playerId>`, `join_address.dart`); a new device joining with it
  takes over that player's existing balance and properties (and updates
  the display name) instead of becoming a new player — server-side this
  needs no special handling at all, since a join with an existing,
  `hasLeft` player id is already just how a normal rejoin works. Client-
  side, playing as a claimed identity for one specific game (rather than
  this device's own permanent one) is handled by `GameProvider.myPlayerId`
  preferring the game's own `GameRecord.myPlayerId` over
  `IdentityService.playerId`.
- **Chance / Community Chest**: quick actions draw the next card off the
  board's deck **on the server** — a shuffled pile per deck, dealt in order
  and reshuffled from scratch only once it runs out, like a physical stack
  (not an independent random pick each time, which could repeat the same
  card); revealed in a dialog on every device — but not all at once: the
  server resolves a roll's landing (and broadcasts the card) *before* it
  broadcasts the roll itself, so the card would otherwise reach every other
  device before the drawer has necessarily even seen their own dice result.
  Each device holds off showing anyone else's copy of the dialog until that
  player's own device signals (`dismissRoll` intent → `rollDismissed` event)
  that its own copy is about to appear — which, for a roll-triggered draw,
  is already gated behind that device's own dice sheet closing, and for a
  manual quick-action draw (no dice sheet involved) fires immediately. A
  generous timeout (`GameScreen`, 10s) covers the drawer's device never
  sending it (crashed, backgrounded, disconnected). Money effect
  auto-applied as a `card` transaction. A card is exactly one of: a money
  card, a **"go to
  X" move card** (`BoardCard.moveToPropertyId`, authored via a Money/Move
  to property/Move by spaces/Get out of jail free/Building repairs toggle)
  — drawing one
  moves the drawer's token straight to that square (paying GO salary if
  passed/landed on, same as a normal roll) and resolves whatever is there
  exactly like landing on it normally would — **except** a card targeting
  the plain Jail square is treated the same as targeting the dedicated Go
  To Jail square: it arrests the player (`inJail = true`) and never pays GO
  salary even if passed, rather than the harmless "just visiting" a normal
  dice landing on the plain Jail square gives — nobody authors a "go to
  jail" card meaning a casual drop-by — a **relative move card**
  (`BoardCard.moveBySpaces`, e.g. the classic "Go Back 3 Spaces") — a
  signed step count applied directly (never normalized into a forward
  distance), so it never pays GO salary even if it happens to land exactly
  on GO, matching the physical rule that backing up onto GO doesn't
  collect — a **Get Out of Jail Free card** (`BoardCard.grantsJailCard`):
  instead of an immediate effect, the drawer holds onto it
  (`Player.jailCards`) and it leaves its deck's rotation (excluded from the
  next reshuffle) until they use it from the jail banner to leave for free
  — no fine, no roll (`useJailCard` intent, resolved via a dedicated
  `jailCardUsed` event since no money moves, same pattern as
  `transferProperty`) — or a **building repairs card**
  (`BoardCard.perHouseCharge`/`perHotelCharge`, e.g. "pay $40 per house,
  $115 per hotel"): unlike every other money card, it has no fixed
  `amount` — the bill is computed at draw time from the drawer's own
  buildings across every property they own
  (`GameEngine.computeBuildingRepairs`, counting a hotel as a hotel, not
  as 5 houses) and broadcast as `chargedAmount` alongside the card so
  every device shows the actual amount, not the card's (unused, always 0)
  `amount` field. Move/jail-card kinds are only meaningful on boards
  with a curated layout; building repairs works on any board (it only
  needs ownerships, not position). Boards with empty decks get a hint to
  add cards in the editor.
- **Landing auto-opens the property sheet**: on a board with a curated
  layout, whenever your own roll (or a "go to X" card) moves your token
  onto a street/railroad/utility, that property's sheet pops open — buy,
  pay rent, or manage buildings without digging through Properties
  (`GameScreen._maybeOpenLandedProperty`, driven by
  `GameProvider.diceRolls`/`cardDraws`). It doesn't chain in the instant
  the board sheet appears — an earlier version chained straight off the
  board *closing*, which read as a trap. Instead it waits 2s after the
  board pops up, then opens on top of it, still open behind
  (`_afterRollReveal`) — long enough to actually see the token land on the
  board before the sheet appears over it.
- **Pass GO**: salary, doubled if landed on exactly — automatic on boards
  with a curated layout; a manual quick action on boards without one.
- **Not modeled on purpose**: bankruptcy, structured trade offers (property
  transfer + Send covers trades manually), transferring/selling a held Get
  Out of Jail Free card between players (use it or keep it; handing it to
  someone else is still a physical/manual affair, like a property trade's
  cash side) — all candidates for later.
- The **bank** is account id `"bank"` with infinite money; anyone may
  trigger bank payouts (like trusting the physical banker) — every device
  gets a heads-up (a top banner) the moment someone else collects, since
  it's the one action any player can use to hand themselves an arbitrary
  amount and there's otherwise no gate on it.
- **A voluntary payment is blocked unless the payer can fully cover it —
  a forced one goes through regardless**: `GameEngine.applyPayment` takes a
  `forced` flag. For a normal (non-`forced`) payment — Pay rent (including
  the owner-side POS tap), buying a property, building, mortgaging, a
  plain send, a voluntary jail-fine payment, an auction bid/settlement — it
  rejects the payment outright if it would leave the payer short, since the
  payer had a real chance to mortgage or sell *before* taking that action;
  the rejection reason shows on the sender's own device (personalized:
  "You do not have enough money" vs "‹name› does not have enough money",
  based on whether `viewerId` is the payer). A `forced: true` payment —
  landing on Tax, a Chance/Community Chest money card, the fine forced by
  a 3rd failed jail roll — is auto-triggered with no confirmation step for
  the payer to prepare first, so it always goes through and the payer just
  owes the difference until they mortgage or sell to catch up (there's no
  bankruptcy flow to fall back to, and skipping the charge outright would
  either strand the game mid-turn or let it silently vanish). Negative
  balances render as `-$X` (`formatMoney`) and show in red wherever a
  balance is displayed — now only reachable via a `forced` payment.

## Money & data model (`lib/models/`)

All amounts are `int` (negative allowed on `Player.balance` — see above).
All models are hand-written JSON (`toJson`/`fromJson`)
— **no codegen/build_runner, no dartz; errors use records**:
`typedef Result<T>` in `models/result.dart` with `ok()`, `err()`, `.isOk`,
`.error`, `.requireValue`.

- `board.dart` — `Board` (currency, startingBalance, salary, jailFine,
  properties, chanceCards/communityChestCards) + `BoardCard` (text, amount:
  + collect / − pay / 0 none; **or** `moveToPropertyId` — a "go to X" card;
  **or** `moveBySpaces` — a relative move, e.g. "Go Back 3 Spaces"; **or**
  `grantsJailCard`; **or** `perHouseCharge`/`perHotelCharge` — a building
  repairs card (`BoardCard.isBuildingRepairs`); exactly one kind at a
  time). `goIndex`/`jailIndex` are computed getters
  (first `properties` entry of that kind, or -1) — the board layout is
  just `properties` in physical order, not a separate list.
- `property.dart` — `Property` (kind, colorValue, price, rentTiers,
  housePrice, mortgageValue). `PropertyKind`: ownable `street`/`railroad`/
  `utility` (`.isOwnable`), plus non-ownable board squares `go`/`jail`/
  `freeParking`/`goToJail`/`tax`/`chance`/`communityChest` — `tax` reuses
  `price` as its fixed charge; the others need no extra fields.
- `player.dart` — id (device UUID), name, balance, seat (join order = turn
  order), isHost/isOnline/hasLeft, position (index into `Board.properties`),
  inJail, jailTurns (failed jail-escape attempts), jailCards (held Get Out
  of Jail Free cards). `Player.bankId == 'bank'`.
- `game.dart` — `Game` (board travels inside it), `GameRecord` (local role:
  host/client, host address, myPlayerId), `GameSnapshot` (+ freeParkingPot,
  + running `auctions`).
- `game_transaction.dart` — typed: payment, rent, purchase, salary, house,
  request, card, mortgage, tax, freeParking, transfer (a property handed
  over directly — always $0, logged purely as an activity-feed record);
  optional propertyId; note.
- `property_ownership.dart` — propertyId → ownerId + houses (5 = hotel) +
  mortgaged.
- `property_auction.dart` — `PropertyAuction` (propertyId, startedBy,
  currentBid, currentBidderId) — a live, table-held auction; server-memory
  only, not a DB table (see Live auctions above).
- `money_request.dart`, `dice_roll.dart`, `ws_message.dart` (envelope:
  `{type, payload}` with `MessageType` enum).

## Protocol (`ws_message.dart`)

Intents (client→server): `joinRequest` (optional `spectator: true` — see
Spectator mode below), `paymentIntent` (optional requestId
settles a money request), `buyProperty` (optional price = auction bid),
`payRent` (optional payerId = owner-side POS charge), `setHouses`,
`mortgage` (propertyId + mortgage bool), `transferProperty` (propertyId +
toId; resolves via propertyChanged's txId), `moneyRequest`, `moneyRequestResponse` (decline by target / withdraw by
requester), `rollDice`, `drawCard`, `editTransactionNote`, `payJailFine`,
`useJailCard` (resolves via jailCardUsed's txId, moves no money),
`startAuction`, `placeBid`, `closeAuction`, `endTurn`, `leaveGame`,
`dismissRoll` (a drawer's device signals it's about to show its own copy
of a just-drawn Chance/Community Chest card's dialog — see below),
`kickPlayer` (host-only; see Kick / Replace above).

Events (server→client): `joinAccepted`/`joinRejected`, `snapshot`,
`paymentApplied` (tx + full player list + freeParkingPot), `paymentRejected`,
`propertyChanged`, `transactionNoteUpdated`, `moneyRequested`,
`moneyRequestResolved` (sent to BOTH parties), `jailCardUsed` (txId +
updated player — no money moves, same pattern as propertyChanged),
`diceRolled` (roll +
turnRolled + full player list, since a curated-layout board also moves
tokens on every roll + freeParkingPot), `cardDrawn` (+ full player list,
since a "go to X"/jail card can move or grant a card to the drawer), `turnChanged`,
`playerJoined`, `playerLeft`, `presenceChanged`, `gameClosed`,
`auctionStarted`/`auctionBid` (auction state), `auctionClosed`
(propertyId + winnerId/amount, or cancelled + reason), `auctionRejected`
(sent only to the sender — bid too low, can't afford it, etc), `rollDismissed`
(playerId — a pure relay of `dismissRoll`, see below), `kicked` (sent only
to the removed player, right before the server closes their connection).

Intent ids (txId) make retries idempotent; pending intents resolve via
completers in `GameProvider` with timeouts. `payJailFine` has no dedicated
event — it settles like any other payment, via `paymentApplied`.
`useJailCard` moves no money, so it can't lean on the transaction-id dedup
the others get for free — a retried intent is instead made harmless by the
`!player.inJail` guard itself (a second attempt after the first succeeded
just gets rejected as "not stuck in jail"), the same way `transferProperty`
resolves via its own event rather than `paymentApplied`. Auction
intents aren't txId/completer-based — they're fire-and-forget like
`rollDice`/`drawCard`, since bidding is inherently multi-user/live rather
than a single request-response; rejections surface via the `errors` stream.

### Spectator mode

A read-only viewer (e.g. a TV running the dashboard) joins with
`spectator: true` in its `joinRequest`. The server
(`GameServer._handleSpectate`) never creates a `Player`, never binds a
playerId to the connection (so no intent from it is ever dispatched — the
per-connection dispatch loop drops any message until a playerId is bound),
and just adds the socket to a `_spectators` set that rides every
`_broadcast` alongside `_connections`. Client-side, `GameProvider.watchRoom`
sets `_spectating` and skips all local DB persistence
(`_persistLocally` gates every write, and `_applySnapshot`/`_applyPayment`
skip `upsertGameRecord`/`saveSnapshot` too) — a spectator session is never
saved to this device's games list, and reconnects carry the flag through
(`_scheduleReconnectIfResumable` passes `spectator: _spectating`).
`GamesTab`'s "Watch a room's dashboard" pushes `JoinGameScreen(spectator:
true)`, which needs no player name and lands on `DashboardScreen` instead
of `GameScreen`. `DashboardScreen` is inherently read-only (no action
buttons — the only entry point off it is tapping a property, whose buy/
pay-rent/build controls are already gated by `canResolve`/`canAct`, both
false for a spectator since no `Player` ever matches their id); `AuctionCard`
and the transaction-note editor additionally hide their controls behind
`!isSpectating` for the same reason bidding and note edits would otherwise
render as live but silently no-op (the server drops them at the same
unbound-playerId gate).

## Services (`lib/services/`) — logic lives here, screens stay thin

- `game_engine.dart` — pure rules: applyPayment, validatePurchase (rejects
  non-ownable kinds), computeRent, validateHouses (group rule), nextTurn,
  advancePosition (modular-arithmetic move + GO crossing/landing, GO can
  sit anywhere in the layout), resolveJailRoll (doubles escape / stuck /
  forced-pay-on-3rd-attempt), computeBuildingRepairs (the "pay per house/
  hotel" card's bill, from the drawer's ownerships). Unit-tested.
- `game_server.dart` — sockets + state + persistence + broadcast; also
  serves the bundled web app; dice + card draws happen here. `_handleRollDice`
  also moves the roller's token and resolves the landing square
  (`_movePlayer`/`_resolveLanding`) on boards with a curated layout;
  `_resolveJailTurn`/`_handlePayJailFine`/`_handleUseJailCard` implement the
  jail rule; `_chanceDeck`/`_chestDeck` are each deck's shuffled draw pile,
  `_chanceCardsOut`/`_chestCardsOut` track jail cards currently held by a
  player (excluded from reshuffles until used, via `_returnJailCard`).
  `_handleStartAuction`/`_handlePlaceBid`/`_handleCloseAuction` run live
  auctions purely in memory (`_auctions`); `_spectators` is a parallel set
  of read-only sockets that get every broadcast but never a bound playerId.
- `game_client.dart` — transport only (web_socket_channel).
- `database_service.dart` — sqflite; v4 schema: `boards`, `games`
  (+current_turn_id, last_roll, turn_rolled — roll state survives a host
  restart, so reopening the app mid-turn doesn't grant a fresh roll —
  +free_parking_pot), `players`, `game_transactions`, `game_properties`
  (all JSON columns; `Player.position`/`inJail`/`jailTurns`/`jailCards` and
  the new `PropertyKind`s need no schema change, they're just more JSON
  fields).
  Desktop = sqflite_common_ffi; web =
  sqflite_common_ffi_web (needs `web/sqflite_sw.js` + `web/sqlite3.wasm`,
  installed via `dart run sqflite_common_ffi_web:setup`). Host's DB is the
  record; clients cache snapshots/events for offline viewing and resume.
- `discovery_service.dart` — bonsoir advertise/browse (not on web).
  Services are named by **game id** (display names collide and mDNS
  auto-renames, creating duplicates); rooms are keyed by game id and only
  listed after a quick TCP probe succeeds (mDNS caches outlive
  force-closed hosts, which used to leave ghost rooms).
- `identity_service.dart` — device UUID + display name.
- `nfc_service.dart` — see NFC below.

## Providers (`lib/providers/`, package:provider)

- `GameProvider` — THE session object (host or client, or a read-only
  spectator): state, all actions
  (sendPayment/collectSalary/buyProperty/payRent/setHouses/requestMoney/
  respondToIncomingRequest/rollDice/drawCard/editTransactionNote/
  payJailFine/useJailCard/startAuction/placeBid/closeAuction/endTurn),
  `watchRoom`
  (spectator join), reconnect, LAN IP
  (`roomEndpoint` — network_info_plus with NetworkInterface fallback for
  Windows), `errors` + `cardDraws` + `diceRolls` streams,
  `canAct`/`canResolve`/`canRoll`/`canEndTurn`/`canPayJailFine`/
  `canUseJailCard`,
  `freeParkingPot`, `auctions`/`auctionFor`, `isSpectating`.
- `GamesProvider` (home list), `BoardsProvider` (board CRUD).

## Screens & UX conventions

Flat layout: `lib/screens`, `lib/widgets`, `lib/theme`, `lib/utils`.

- `home_screen` → `games_tab` (games list; "Live" badge = every saved game's
  last-known host answering a quick, bounded TCP probe
  (`_probeReachability`, same idea `discovery_service` already uses for
  mDNS-found rooms), run on load, every 8s while this tab is on screen, and
  on pull-to-refresh — including whichever game this device is currently
  connected to: `GameClient` has no ping/heartbeat of its own, so
  `ClientStatus` can keep reading "connected" for a while after a host
  vanishes without a clean socket close (killed, network drop), and a
  fresh `false` probe result overrides that stale belief rather than the
  other way around. A game hosted elsewhere shows live without having to
  be opened first; tapping opens instantly and connects in background;
  "Watch a room's dashboard" connects read-only as a spectator instead —
  see Spectator mode — and lands on `dashboard_screen` without adding
  anything to this list) + `boards_tab`
  (editor, duplicate, clipboard copy/paste, file import/export via
  file_selector — desktop-only save dialog). No boards are bundled by
  default — hosting requires creating or importing at least one.
- `game_screen` — the banking app: balance card (connection chip + turn pill
  with dice result), a jail banner (use a held Get Out of Jail Free card,
  pay the fine, or roll for doubles) when
  I'm in jail, roll/end-turn row (only on my turn), quick actions (Send,
  Request, Scan & pay, Receive, Pass GO, Collect, Chance, Chest —
  Send/Collect/GO/Chance/Chest gated by `canResolve`,
  Request/Receive/Scan & pay never (see turn flow above); **Pass GO is
  hidden once the board has a curated
  layout**, since it pays automatically then), players row (balances under
  names, accent ring = current turn, long-press → send/request/payment
  card, plus — host viewing another player — remove/replace them (see
  Kick / Replace above)), properties summary, activity teaser (10) →
  `activity_screen`
  (full). On boards with a curated layout, an app-bar toggle
  (`widgets/ring_board.dart`-backed `BoardLayoutView` in a **modal**
  `showModalBottomSheet` — blocks the rest of the screen like any other
  sheet, dismissible via its own close button, a drag, or tapping outside,
  same as any normal sheet) shows/hides the board on demand, and it also
  **pops up automatically on any roll** (`GameProvider.diceRolls` stream —
  every device sees every roll, so token movement is visible wherever a
  player is looking) if it isn't already open. It stays open until
  whoever's looking at it closes it (however they choose to) — no timer,
  no auto-close on any device. For
  my own roll, the popup order is dice result → board (pops up and stays
  open) → a 2s pause → landed property's sheet on top of it
  (`_afterRollReveal`, chained on `_rollUiChain`), so the board actually
  gets seen before the sheet appears over it, instead of the sheet
  chaining in the instant the board is dismissed (an earlier version did
  that, and it read as a trap). A card that doesn't move the
  drawer (money, jail, repairs) skips the property re-check — only a "go
  to X"/"go back N" card re-opens it, since only those actually change
  where the token is standing. Any running auction shows as an `AuctionCard` above the
  roll/end-turn row, visible to the whole table regardless of turn.
  **Responsive**: ≥900px
  fills the whole window — banking column (flex 7, 8-column quick actions)
  + activity pane (flex 3); narrow stays a max-640 column. Global
  listeners here: incoming-request dialog, card-drawn dialog,
  board-popup-on-roll, NFC watch (only acts when this screen is
  top-most).
- `widgets/board_layout_view.dart` — read-only render of `Board.properties`
  as a **physical ring** around a square grid
  (`widgets/ring_board.dart` + `utils/board_ring.dart`: perimeter cells of
  the smallest NxN grid that fits the square count, board-agnostic — a
  classic 40-square board gets an 11x11 grid, same as the real thing),
  corner-to-corner in list order, with every player's token shown as a
  small `PlayerAvatar` (initials + their consistent color, not just a
  plain dot) at their current square, plus who owns each ownable square —
  the **whole tile tinted in the owner's avatar color** (a thin strip
  above the group-color band used to be there, but read as unnoticeable
  from across a room; a warning tone replaces it once mortgaged) — and its
  house/hotel icons. Each square's own group-color band sits on whichever
  side faces the board's center, not always the top — a top-row square is
  banded along its bottom, a left-column one along its right, and so on
  (`BoardLayoutView` classifies every square by row/col via
  `utils/board_ring.dart`'s `ringCells`, corners resolving to their row's
  edge since they aren't ownable and carry no band anyway) — like a real
  board rather than a plain top-of-tile strip. Tapping an ownable square opens
  its sheet directly via `showPropertySheet` (see below) — not the full
  Properties list. `RingBoard` renders
  **rectangular** edge squares (tall/narrow on top & bottom, wide/short on
  the sides, like a real board) with big square corners rather than
  forcing every square to the same small square, scaled to fit the
  available width via a plain `FittedBox` — **static, no scroll, no zoom**
  (earlier scroll/pinch-zoom versions were tried and explicitly rejected;
  don't reintroduce `InteractiveViewer` or scrollables here). Shared by
  `game_screen`'s board toggle/popup and embedded in `dashboard_screen`.
  Every token carries its own continuous, radar-style pulsing ring
  (`_TokenRadarPulse`, staggered per seat so tokens sharing a square don't
  blip in lockstep) so where everyone currently stands reads at a glance,
  like a radar sweep, not just right after they move. Token movement
  itself is instant, not animated (still deferred) — only the pulse is
  new.
- `properties_screen` — search, ownership list (ownable kinds only —
  specials live in the board view, not here), per-property sheet (rent
  table, buy/pay-rent/build with **confirmation dialogs**, errors shown
  inside the sheet). The sheet itself — buy/pay-rent/build, mortgage,
  transfer, and (only for the owner, when NFC is available) a hint that
  another player can tap their card here to pay rent — is
  `showPropertySheet(context, propertyId:, nfcAvailable:)`, a top-level
  function any screen can call directly rather than going through this
  list: `game_screen` uses it for landings, NFC taps, and tapping a square
  on the board popup, and `dashboard_screen` for tapping a square there
  too — none of them navigate through this screen first anymore, only
  browsing the full list ("View all") actually opens it. Registering a
  physical NFC card for a property is a separate, explicit icon in this
  screen's own app bar, only relevant while actually browsing the list.
  An unowned property with no auction shows
  Buy plus, for whoever is actually standing on it on their turn, an explicit
  **"Decline — start an auction"** button (the official rule: declining a
  landing forces an auction rather than leaving it unowned indefinitely) —
  anyone else just sees a plain "Start an auction" link instead, since
  there's no landing of theirs to decline. Once one's running its
  `AuctionCard` replaces both.
- `send_money_screen` — modes pay/collect/request; recipient bubbles; keypad
  (`00` appends atomically); request mode shows the target's balance and
  blocks over-asking; NFC tap-to-pay (amount first → tap card → confirm).
  Paying a specific player (not collecting, not requesting) confirms with a
  dialog before the money actually moves, same as NFC tap-to-pay already
  did — collecting from the bank stays one-tap (it's already flagged to
  the rest of the table as it happens) and a request doesn't move money
  until the other side accepts it.
- `dashboard_screen` — table-wide view for big screens (players grid, turn +
  dice banner, running `AuctionCard`s, shared activity feed, and the board
  view when the board has a layout). Reachable either as a normal player
  (in-game popup menu → Dashboard) or, without ever joining, via
  `games_tab`'s spectator "Watch" entry.
- `board_editor_screen` — properties order **is** the board layout, edited
  either as a `RingBoard` (default — long-press and drag a square to where
  it belongs, tap to edit, empty ring slots add there) or, via a toggle, a
  `SliverReorderableList` inside a `CustomScrollView` (drag near the top/
  bottom edge auto-scrolls the page). Adding a property picks any
  `PropertyKind` (not just street/railroad/utility) via a dropdown;
  ownable-only fields (color, price, mortgage, house cost, rent tiers)
  show conditionally, Tax shows a single amount field (`Property.price`
  reused), other specials
  need only a name.
- `scan_pay_screen` (mobile_scanner; `canScanQr` excludes Windows/Linux),
  `receive_money_sheet` (my QR, optional fixed amount, auto-closes when
  paid), `web_join_screen`, `host/join` screens. `join_game_screen` adds a
  `scan_join_screen` entry point (a `qr_code_scanner_rounded` suffix icon
  inside the address field, same `canScanQr` gate) for devices mDNS
  doesn't reach — scans the same join link the room QR/"copy link" encode
  and reuses `utils/join_address.dart`'s parser (also backing the manual
  address field) rather than duplicating the host/port parsing.
  `scan_pay_screen`/`scan_join_screen` share `widgets/qr_scan_view.dart` —
  a `MobileScanner` restricted to a centered square `scanWindow` (so a
  second QR elsewhere in frame is ignored) with a dimmed, bracketed
  viewfinder overlay drawn around it.
- Widgets: `balance_card` (trailing + footer slots), `transaction_tile` →
  `transaction_details_sheet`, `activity_feed.dart`
  (`buildActivityFeed(context, session, limit)` — day headers + running
  balance, shared by game/dashboard/activity), `player_card_sheet` (debit-
  card styled, "Register a physical card"), `player_avatar` (presence dot,
  highlight ring; color is keyed by **seat**, not a hash of the player id
  — `AppColors.avatarColorForSeat` — so two players at the same table
  never collide on a color, unlike the old id-hash scheme; the 8-color
  palette itself is one hue per player, no near-duplicate shades of the
  same color, aside from a deliberate sky-blue/navy-blue pair),
  `auction_card.dart` (one live auction: current bid,
  who's leading, bid box, close button — read-only for spectators),
  `amount_keypad`, `section_header`, `empty_state`.
- Theme (`app_theme.dart`): violet fintech accent #635BFF, hero gradient,
  radius 22, light+dark, **Inter**, bundled as a local asset
  (`assets/fonts/InterVariable.ttf`, `pubspec.yaml` `fonts:`) rather than
  google_fonts: a runtime download would re-layout the app whenever a
  weight arrives (visible flicker) and fail with no internet, but the
  platform-default font Flutter otherwise falls back to isn't actually
  consistent everywhere — web has no Roboto of its own and was rendering
  a generic browser sans-serif, looking different from every native
  build. A bundled asset fixes that without a runtime fetch.
  `FloatingLabelBehavior.always` (narrow numeric fields
  clip full-size labels). Money formatting via `utils/formatting.dart`
  (intl): formatMoney/formatSignedMoney/formatWhen/formatDay
  (`formatMoney` renders a negative balance as `-$X`, not `$-X`). All
  snackbars go through `utils/snack.dart` (`showSnack`/`showSnackWith`):
  the previous bar is removed instantly, 2s duration — never queue. That's
  for direct feedback on an action the viewer themselves just took, though
  — it anchors to the page's own Scaffold, so it renders *behind* anything
  pushed on top (a modal sheet, a dialog). For ambient notices about
  something someone *else* just did (a dice roll, a bank collection, rent
  or a payment landing in my account, a join link copied from the room-info
  sheet), `widgets/activity_banner.dart`'s `showActivityBanner` inserts
  into the root `Overlay` instead, so it stays visible regardless of what
  else is open — one persistent `OverlayEntry` (`_ActivityBannerHost`, kept
  alive for the app's lifetime) hosts every banner ever shown from
  anywhere, stacked in a `Column` so a burst of events (several roll/rent
  notices firing close together) queues underneath rather than each one
  landing at the same `top: 0` spot and silently covering whatever was
  already there — capped at 3 stacked at once, oldest dropped first. Each
  card mirrors `ActivityFeed`/`TransactionTile`'s own visual language (icon,
  title, meta, colored amount) rather than a plain icon-and-text strip, and
  dismisses on its own 5s timer or on tap.

## NFC (Android)

`NfcService.instance` (singleton — one radio). Payloads are NDEF text:
`digipoly:prop:<boardId>:<propertyId>` and `digipoly:player:<playerId>`
(player cards work across games). Parsed to sealed `NfcCardData`.

- A **persistent watch session** runs while `game_screen` is open: tapping
  any Digipoly card just works (property → its sheet; player → Send
  prefilled, turn-gated) AND keeps Android's system "new tag" UI away (an
  active reader session owns the radio). The watch only fires when the game
  screen is the top route — pushed screens have their own affordances.
- One-shot read/write ops (register cards, send-screen recipient pick)
  pause the watch and hand the radio back after; the session lingers 3s
  after one-shots so the system UI can't grab the still-present tag.
- **POS mode in the property sheet**: while a property's sheet is open it
  takes over the watch (`setWatchOverride`/`clearWatchOverride`) — tapping
  that property's card or your own payment card triggers the primary
  action (buy if unowned, pay rent if someone else's), with the normal
  confirmation dialog. Wrong cards / not-your-turn show an inline hint.
- **Owner-side POS (charge rent by tap)**: when the sheet's property is
  *mine*, my device is the terminal — another player taps *their* payment
  card on it and their account is charged the rent (confirmation dialog on
  my side; the tap is the payer's authorization, like tap-to-pay). Wire:
  `payRent` intent with optional `payerId`; the server only accepts it
  from the property's owner, uses the payer's in-app roll for utilities,
  and books the transaction payer → owner as usual.
- Cancel resolves pending ops with sentinel `NfcService.cancelled` (flows
  treat it as silence). Errors truncated to 90 chars.
- Manifest: NFC permission (feature optional), plus an NDEF_DISCOVERED
  text/plain intent-filter so taps outside the app open Digipoly instead of
  the system sheet.
- Design note: cards identify their **owner** (tap someone's card to pay
  them) — the inverse of Hasbro's banker unit. "POS mode + PIN" is a
  possible future feature.
- **Web NFC is a dead end for the iOS-web audience**: the Web NFC API
  exists only in Chrome on Android; iOS Safari/WebKit exposes no NFC to web
  pages at all (Apple keeps Core NFC native-only). Since the web build
  exists precisely for iPhones (APK sideload covers Android), web NFC is
  not implemented — iOS web users pay via QR (scan + Receive both work in
  the browser).

## QR payments & web join

- `utils/pay_code.dart`: `digipoly:pay:<gameId>:<playerId>:<amount>`
  (amount 0 = payer types it). Receive sheet shows it; scan screen parses
  it → Send prefilled.
- Room QR (game app bar) encodes `http://<ip>:47912/`; the same link is
  what the room-info sheet copies, and the Join screen's manual field
  accepts a pasted link as well as a bare IP. A host's "Replace this
  player" link (see Kick / Replace above) is the same link plus
  `?claim=<playerId>`.
  The server can serve the **web app itself**: `tool/bundle_web_app.ps1`
  builds web + zips into `assets/web/web_app.zip` (gitignored); server
  serves it via a shelf Cascade. Scanning the QR on any phone opens the
  game in the browser → `web_join_screen` asks a name → joins directly.
  `main.dart` detects this by checking whether the page's own origin
  (`Uri.base`) is a plain-http LAN address rather than parsing query
  params for that — a `claim` param, if present, still rides along into
  `WebJoinScreen`.
- Web builds can't host (dart:io throws at runtime, guarded by kIsWeb) or
  use NFC/mDNS; sqlite works via the wasm worker files in `web/`.

## Platform matrix

| Capability | Windows | Android | Web |
|---|---|---|---|
| Host a room | ✅ | ✅ | ❌ |
| Join | ✅ | ✅ | ✅ (QR/URL or manual IP) |
| mDNS discovery | ✅ | ✅ | ❌ (manual/URL only) |
| NFC | ❌ | ✅ | ❌ |
| QR scanning | ❌ (`canScanQr`) | ✅ | ✅ |
| Show QR codes | ✅ | ✅ | ✅ |

## Dev workflow

```
flutter pub get
flutter run                     # Windows or Android
flutter analyze && flutter test # keep both clean (engine has unit tests)
.\tool\bundle_web_app.ps1       # optional: embed web build for browser-join
```

VS Code task "Build all (bundle web + Android + Windows)" (`.vscode/tasks.json`,
bound to the default build task) runs the web bundle then both native builds
in sequence, so the embedded web app is always fresh.

Android manifest already has INTERNET/multicast/NFC permissions. iOS folder
doesn't exist (would need bonsoir Info.plist keys + NFC entitlements).

## Conventions (important)

- No code generation / build_runner. No dartz — Dart records for results.
- Flat `lib/` structure (no feature folders / clean-architecture layers);
  separation of concerns by class.
- provider for state; every addition should push toward "a real banking
  app" look & feel; clean modern UI, not basic.
- Verify with `flutter analyze` + `flutter test` after changes.

## Roadmap / not yet implemented

Animated token movement (today's board view updates positions instantly —
no sliding/path animation, though every token now carries a continuous
radar-style pulse, see `_TokenRadarPulse` in `board_layout_view.dart`) and a
geometrically accurate ring layout (today it's a reading-order wrapping
grid) — both explicitly deferred as a "static first" step before polish.
Structured trade offers (property+cash in one
accepted bundle — plain transfer + Send exists), bankruptcy flow, settings
screen (profile, theme, per-game house-rule toggles — e.g. make the strict
turn-gating optional, double-GO, or the Free Parking pot optional/off),
POS mode with PIN for cards, net-worth stats/charts from the transaction
log, game-end summary, sounds/haptics, community board catalog
(currently P2P: boards travel with games, clipboard text, .json files; no
central server by design). **Bank loans, with interest** — not an official
Monopoly rule (the real game only has mortgaging, selling houses back, and
trading to raise cash; short of that, you go bankrupt — no bankruptcy flow
exists here either, see above) but a deliberate house-rule addition in the
same spirit as the Free Parking pot, and one that leans into this app
being modeled as a real banking app rather than just a digital version of
the board game. Explicitly deferred: a separate feature, its own commit,
only after the current round of bug fixes lands.
