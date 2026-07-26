# Digipoly

Digital banking for Monopoly-style board games. Keep the physical board, dice
and tokens — replace the paper money with your phones. Everything runs on
your local network: no accounts, no internet, no central server.

## How it works

One device **hosts** a room and becomes the bank's source of truth. Everyone
else **joins** over wifi — from the app, or straight from a browser by
scanning the room's QR code. Payments, rents, purchases and salaries are sent
as intents to the host, validated there, and broadcast live to every player.

Boards are plain data: describe the physical board in your hands once
(currency, properties, rents, chance & community chest cards) and it travels
inside every game you host — players who join never need to recreate it.

## Features

- **Banking**: send money, collect from the bank, Pass GO salary, request
  money from other players (they approve on their device)
- **Properties**: buy, build houses/hotels, pay auto-computed rent
  (full-group double rent, railroad counts, utility dice multipliers)
- **Turns**: optional turn rotation with an End Turn button
- **Dashboard**: a table-wide live view for any big screen
- **Boards**: editor, duplicate, and offline sharing — copy a board as
  text, or save the board from any game you joined
- **NFC property cards** (Android): write a property to a physical card,
  tap it in-game to buy or pay rent
- **Resilient sessions**: your seat and balance survive app restarts and
  connection drops; games resume from the home screen

## Join from a browser

Bundle the web build into the app once:

```
.\tool\bundle_web_app.ps1
flutter build apk             # rebuild so the asset ships
```

The host's room then serves the app itself on the room port — scanning the
room QR opens the game in any browser on the wifi, asks for a name, and joins
directly.

## Development

```
flutter pub get
flutter run            # Windows, Android
flutter test
```

The project is intentionally flat: `lib/models`, `lib/services`,
`lib/providers`, `lib/screens`, `lib/widgets`, `lib/theme`. No code
generation, no build_runner. State management is `provider`; networking is
`shelf`/`shelf_web_socket` on the host and `web_socket_channel` on clients,
with `bonsoir` for room discovery (mDNS).

## About this project

Digipoly's architecture, game rules, and UX were designed by the author; the
implementation was written with Claude (Anthropic) as a pair-programming
assistant, with every change reviewed and tested by the author before being
kept. See [PROJECT.md](PROJECT.md) for the full design and architecture
notes, and [CLAUDE.md](CLAUDE.md) for the conventions given to the assistant.
