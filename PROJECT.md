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
    — free-form sends, collecting from the bank, Scan & pay — and landing
    effects: buying the square you're on, paying its rent, Chance/Community
    Chest, Pass GO. Post-roll sends matter because taxes and card effects
    ("pay each player…") are settled via Send after landing.
  "End turn" stays disabled until you rolled (enforced server-side too).
  Exceptions: **requesting money and answering a money request are allowed
  anytime** (like showing a Receive code).
- **Dice are server-side**: one roll per turn, only by the current player
  (`rollDice`/`diceRolled`), same result on every device, shown on the
  balance-card turn chip, dice sheet and dashboard. **Doubles roll again**:
  a double leaves the turn un-rolled server-side, so the player gets (and,
  since ending requires a roll, must take) another throw — unless that
  double's move sends them to jail, which cancels the bonus roll. No
  three-doubles-to-jail rule (only landing on Go To Jail sends you there).
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
    Monopoly, added because the user wanted it).
  - Landing on Go To Jail teleports to `Board.jailIndex`, sets `inJail`.
  - Landing on Chance/Community Chest auto-draws a card (same server logic
    as the manual quick action, just triggered by the landing).
  - Buying, paying rent, and mortgaging stay fully manual/confirmed, as
    always — only the *detection* of what square you're on is new.
- **Jail** (only reachable via a Go To Jail square): on your turn, pay
  `Board.jailFine` anytime before rolling to leave immediately, or roll —
  doubles escape free and move that roll, non-doubles add a failed attempt
  (`Player.jailTurns`), and the 3rd failed attempt forces paying the fine
  (still moving that roll). Get-out-of-jail-free cards stay physical/
  outside the app (selling one is a plain payment), as before.
- **Properties**: buy (list price), build houses 0–4 + hotel (=5). A plain
  buy is only valid for the square your own token is actually on (checked
  both client- and server-side via `GameEngine.validatePurchase`'s position
  check) — boards with no curated layout track no position, so the
  restriction doesn't apply there. Building
  requires owning the **whole color group** and follows the **even-building
  rule**: no street of the group may end up more than one house apart from
  another — building spreads across the group, selling comes off the
  tallest first (hotel counts as 5). Hotel only via 4 houses (stepper is
  ±1). Sell-back refunds half. Rent auto-computed: street tiers, double
  base rent on a full unbuilt group, railroads by count owned, utilities =
  multiplier × dice (uses the payer's own in-app roll automatically).
- **Live auctions**: any connected player can start an auction for an
  unowned property from its sheet ("Start an auction") — not turn-gated,
  since auctions arise on other players' turns. Everyone connected sees a
  shared live `AuctionCard` (game screen, dashboard, and the property
  sheet) with the current bid and who's leading; anyone can raise it
  anytime, no turn order, as long as it beats the current bid and they can
  afford it; anyone can close it, selling to the top bidder at their bid
  (skips the "must be standing on it" check, same as any explicit-price
  buy) or cancelling if nobody bid. State lives server-side only
  (`GameServer._auctions`, `PropertyAuction` model) — not persisted to the
  DB, but replayed to (re)connecting clients via the snapshot, so a table
  restart or reconnect doesn't need to restart mid-auction. Wire:
  `startAuction`/`placeBid`/`closeAuction` intents,
  `auctionStarted`/`auctionBid`/`auctionClosed`/`auctionRejected` events.
- **Trades (property transfer)**: the owner hands a deed to another player
  from the property sheet ("Transfer to another player" → pick → confirm).
  No money moves — the deal's cash is a normal Send; buildings must be
  sold first, a mortgage travels with the property. Not turn-gated (trades
  happen anytime at the table). Wire: `transferProperty` intent; the
  `propertyChanged` broadcast carries the intent's `txId` so the sender's
  pending future resolves (transfers book no transaction).
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
- **Chance / Community Chest**: quick actions draw a random card from the
  board's deck **on the server**; revealed in a dialog on every device;
  money effect auto-applied as a `card` transaction. A card is either a
  money card or a **"go to X" move card** (`BoardCard.moveToPropertyId`,
  authored in the board editor via a Money/Move to property toggle) —
  drawing one moves the drawer's token straight to that square (paying GO
  salary if passed/landed on, same as a normal roll) and resolves whatever
  is there exactly like landing on it normally would; only meaningful on
  boards with a curated layout. Boards with empty decks get a hint to add
  cards in the editor.
- **Landing auto-opens the property sheet**: on a board with a curated
  layout, whenever your own roll (or a "go to X" card) moves your token
  onto a street/railroad/utility, that property's sheet pops open right
  away — buy, pay rent, or manage buildings without digging through
  Properties (`GameScreen._maybeOpenLandedProperty`, driven by
  `GameProvider.diceRolls`/`cardDraws`).
- **Pass GO**: salary, doubled if landed on exactly — automatic on boards
  with a curated layout; a manual quick action on boards without one.
- **Not modeled on purpose**: bankruptcy, structured trade offers (property
  transfer + Send covers trades manually), jail escape via a
  get-out-of-jail-free card (those stay physical; selling one = plain
  payment) — all candidates for later.
- The **bank** is account id `"bank"` with infinite money; anyone may
  trigger bank payouts (like trusting the physical banker).

## Money & data model (`lib/models/`)

All amounts are `int`. All models are hand-written JSON (`toJson`/`fromJson`)
— **no codegen/build_runner, no dartz; errors use records**:
`typedef Result<T>` in `models/result.dart` with `ok()`, `err()`, `.isOk`,
`.error`, `.requireValue`.

- `board.dart` — `Board` (currency, startingBalance, salary, jailFine,
  properties, chanceCards/communityChestCards) + `BoardCard` (text, amount:
  + collect / − pay / 0 none; **or** `moveToPropertyId` — a "go to X" card,
  never both). `goIndex`/`jailIndex` are computed getters
  (first `properties` entry of that kind, or -1) — the board layout is
  just `properties` in physical order, not a separate list.
- `property.dart` — `Property` (kind, colorValue, price, rentTiers,
  housePrice, mortgageValue). `PropertyKind`: ownable `street`/`railroad`/
  `utility` (`.isOwnable`), plus non-ownable board squares `go`/`jail`/
  `freeParking`/`goToJail`/`tax`/`chance`/`communityChest` — `tax` reuses
  `price` as its fixed charge; the others need no extra fields.
- `player.dart` — id (device UUID), name, balance, seat (join order = turn
  order), isHost/isOnline/hasLeft, position (index into `Board.properties`),
  inJail, jailTurns (failed jail-escape attempts). `Player.bankId == 'bank'`.
- `game.dart` — `Game` (board travels inside it), `GameRecord` (local role:
  host/client, host address, myPlayerId), `GameSnapshot` (+ freeParkingPot,
  + running `auctions`).
- `game_transaction.dart` — typed: payment, rent, purchase, salary, house,
  request, card, mortgage, tax, freeParking; optional propertyId; note.
- `property_ownership.dart` — propertyId → ownerId + houses (5 = hotel) +
  mortgaged.
- `property_auction.dart` — `PropertyAuction` (propertyId, startedBy,
  currentBid, currentBidderId) — a live, table-held auction; server-memory
  only, not a DB table (see Live auctions above).
- `money_request.dart`, `dice_roll.dart`, `ws_message.dart` (envelope:
  `{type, payload}` with `MessageType` enum).

## Protocol (`ws_message.dart`)

Intents (client→server): `joinRequest`, `paymentIntent` (optional requestId
settles a money request), `buyProperty` (optional price = auction bid),
`payRent` (optional payerId = owner-side POS charge), `setHouses`,
`mortgage` (propertyId + mortgage bool), `transferProperty` (propertyId +
toId; resolves via propertyChanged's txId), `moneyRequest`, `moneyRequestResponse` (decline by target / withdraw by
requester), `rollDice`, `drawCard`, `editTransactionNote`, `payJailFine`,
`startAuction`, `placeBid`, `closeAuction`, `endTurn`, `leaveGame`.

Events (server→client): `joinAccepted`/`joinRejected`, `snapshot`,
`paymentApplied` (tx + full player list + freeParkingPot), `paymentRejected`,
`propertyChanged`, `transactionNoteUpdated`, `moneyRequested`,
`moneyRequestResolved` (sent to BOTH parties), `diceRolled` (roll +
turnRolled + full player list, since a curated-layout board also moves
tokens on every roll + freeParkingPot), `cardDrawn` (+ full player list,
since a "go to X" card moves the drawer's token), `turnChanged`,
`playerJoined`, `playerLeft`, `presenceChanged`, `gameClosed`,
`auctionStarted`/`auctionBid` (auction state), `auctionClosed`
(propertyId + winnerId/amount, or cancelled + reason), `auctionRejected`
(sent only to the sender — bid too low, can't afford it, etc).

Intent ids (txId) make retries idempotent; pending intents resolve via
completers in `GameProvider` with timeouts. `payJailFine` has no dedicated
event — it settles like any other payment, via `paymentApplied`. Auction
intents aren't txId/completer-based — they're fire-and-forget like
`rollDice`/`drawCard`, since bidding is inherently multi-user/live rather
than a single request-response; rejections surface via the `errors` stream.

## Services (`lib/services/`) — logic lives here, screens stay thin

- `game_engine.dart` — pure rules: applyPayment, validatePurchase (rejects
  non-ownable kinds), computeRent, validateHouses (group rule), nextTurn,
  advancePosition (modular-arithmetic move + GO crossing/landing, GO can
  sit anywhere in the layout), resolveJailRoll (doubles escape / stuck /
  forced-pay-on-3rd-attempt). Unit-tested.
- `game_server.dart` — sockets + state + persistence + broadcast; also
  serves the bundled web app; dice + card draws happen here. `_handleRollDice`
  also moves the roller's token and resolves the landing square
  (`_movePlayer`/`_resolveLanding`) on boards with a curated layout;
  `_resolveJailTurn`/`_handlePayJailFine` implement the jail rule.
  `_handleStartAuction`/`_handlePlaceBid`/`_handleCloseAuction` run live
  auctions purely in memory (`_auctions`).
- `game_client.dart` — transport only (web_socket_channel).
- `database_service.dart` — sqflite; v4 schema: `boards`, `games`
  (+current_turn_id, last_roll, turn_rolled — roll state survives a host
  restart, so reopening the app mid-turn doesn't grant a fresh roll —
  +free_parking_pot), `players`, `game_transactions`, `game_properties`
  (all JSON columns; `Player.position`/`inJail`/`jailTurns` and the new
  `PropertyKind`s need no schema change, they're just more JSON fields).
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

- `GameProvider` — THE session object (host or client): state, all actions
  (sendPayment/collectSalary/buyProperty/payRent/setHouses/requestMoney/
  respondToIncomingRequest/rollDice/drawCard/editTransactionNote/
  payJailFine/startAuction/placeBid/closeAuction/endTurn), reconnect, LAN IP
  (`roomEndpoint` — network_info_plus with NetworkInterface fallback for
  Windows), `errors` + `cardDraws` + `diceRolls` streams,
  `canAct`/`canResolve`/`canRoll`/`canEndTurn`/`canPayJailFine`,
  `freeParkingPot`, `auctions`/`auctionFor`.
- `GamesProvider` (home list), `BoardsProvider` (board CRUD).

## Screens & UX conventions

Flat layout: `lib/screens`, `lib/widgets`, `lib/theme`, `lib/utils`.

- `home_screen` → `games_tab` (games list; "Live" badge = actually connected
  now; tapping opens instantly and connects in background) + `boards_tab`
  (editor, duplicate, clipboard copy/paste, file import/export via
  file_selector — desktop-only save dialog). No boards are bundled by
  default — hosting requires creating or importing at least one.
- `game_screen` — the banking app: balance card (connection chip + turn pill
  with dice result), a jail banner (pay the fine or roll for doubles) when
  I'm in jail, roll/end-turn row (only on my turn), quick actions (Send,
  Request, Scan & pay, Receive, Pass GO, Collect, Chance, Chest —
  Send/Scan/Collect/GO/Chance/Chest gated by `canResolve`,
  Request/Receive never; **Pass GO is hidden once the board has a curated
  layout**, since it pays automatically then), players row (balances under
  names, accent ring = current turn, long-press → send/request/payment
  card), properties summary, activity teaser (10) → `activity_screen`
  (full). On boards with a curated layout, an app-bar toggle
  (`widgets/ring_board.dart`-backed `BoardLayoutView` in a non-modal
  `showBottomSheet` panel, so it doesn't block the rest of the screen or
  dismiss on an outside tap) shows/hides the board on demand, and it also
  **pops up automatically on any roll** (`GameProvider.diceRolls` stream —
  every device sees every roll, so token movement is visible wherever a
  player is looking) if it isn't already open, and **landing on an
  ownable square auto-opens that property's sheet** (see the game-rules
  bullet above). Any running auction shows as an `AuctionCard` above the
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
  plain dot) at their current square, plus who owns each ownable square
  (a thin strip in the owner's avatar color, a warning tone once
  mortgaged) and its house/hotel icons; tapping an ownable square opens
  `properties_screen` (`openPropertyId`). `RingBoard` renders
  **rectangular** edge squares (tall/narrow on top & bottom, wide/short on
  the sides, like a real board) with big square corners rather than
  forcing every square to the same small square, scaled to fit the
  available width via a plain `FittedBox` — **static, no scroll, no zoom**
  (earlier scroll/pinch-zoom versions were tried and explicitly rejected;
  don't reintroduce `InteractiveViewer` or scrollables here). Shared by
  `game_screen`'s board toggle/popup and embedded in `dashboard_screen`.
  Token movement is instant, not animated (still deferred).
- `properties_screen` — search, ownership list (ownable kinds only —
  specials live in the board view, not here), per-property sheet (rent
  table, buy/pay-rent/build with **confirmation dialogs**, errors shown
  inside the sheet, NFC write). An unowned property with no auction shows
  Buy plus "Start an auction"; once one's running its `AuctionCard`
  replaces both.
- `send_money_screen` — modes pay/collect/request; recipient bubbles; keypad
  (`00` appends atomically); request mode shows the target's balance and
  blocks over-asking; NFC tap-to-pay (amount first → tap card → confirm).
- `dashboard_screen` — table-wide view for big screens (players grid, turn +
  dice banner, running `AuctionCard`s, shared activity feed, and the board
  view when the board has a layout). Reachable as a normal player via the
  in-game popup menu → Dashboard.
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
  paid), `web_join_screen`, `host/join` screens.
- Widgets: `balance_card` (trailing + footer slots), `transaction_tile` →
  `transaction_details_sheet`, `activity_feed.dart`
  (`buildActivityFeed(context, session, limit)` — day headers + running
  balance, shared by game/dashboard/activity), `player_card_sheet` (debit-
  card styled, "Register a physical card"), `player_avatar` (presence dot,
  highlight ring), `auction_card.dart` (one live auction: current bid,
  who's leading, bid box, close button), `amount_keypad`, `section_header`,
  `empty_state`.
- Theme (`app_theme.dart`): violet fintech accent #635BFF, hero gradient,
  radius 22, light+dark, **platform font only** (no google_fonts —
  offline + flicker), `FloatingLabelBehavior.always` (narrow numeric fields
  clip full-size labels). Money formatting via `utils/formatting.dart`
  (intl): formatMoney/formatSignedMoney/formatWhen/formatDay. All
  snackbars go through `utils/snack.dart` (`showSnack`/`showSnackWith`):
  the previous bar is removed instantly, 2s duration — never queue.

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
  accepts a pasted link as well as a bare IP.
  The server can serve the **web app itself**: `tool/bundle_web_app.ps1`
  builds web + zips into `assets/web/web_app.zip` (gitignored); server
  serves it via a shelf Cascade. Scanning the QR on any phone opens the
  game in the browser → `web_join_screen` asks a name → joins directly.
  `main.dart` detects this by checking whether the page's own origin
  (`Uri.base`) is a plain-http LAN address rather than parsing any query
  params.
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

Animated token movement (today's board view updates positions instantly,
no animation) and a geometrically accurate ring layout (today it's a
reading-order wrapping grid) — both explicitly deferred as a "static
first" step before polish. Structured trade offers (property+cash in one
accepted bundle — plain transfer + Send exists), bankruptcy flow, settings
screen (profile, theme, per-game house-rule toggles — e.g. make the strict
turn-gating optional, double-GO, or the Free Parking pot optional/off),
POS mode with PIN for cards, net-worth stats/charts from the transaction
log, game-end summary, sounds/haptics, community board catalog
(currently P2P: boards travel with games, clipboard text, .json files; no
central server by design).
