# Changelog

All notable changes to this project are documented here. Format based on
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [2.1.0] - 2026-08-30

### Added

- Request rent from the property sheet — if someone lands on your property
  and you notice before they've paid, a quiet "Request rent" button on that
  property's sheet asks them for it, prefilled with the right amount.
- Everyone sees the dice roll, not just the roller — the board popup now
  animates the roll for every connected device, and stays showing on the
  board afterward instead of disappearing.
- End turn locks briefly right after rolling, so a stray tap can't skip your
  turn before you've had a chance to act on what you just rolled.
- Get Out of Jail Free badge shows how many you're holding, instead of just
  a plain icon once you've got more than one.

### Fixed

- The "Start room" button and the bank loan note field could get hidden
  behind the on-screen keyboard on Android.
- Joining a game from a browser over wifi could hang with no clear reason if
  the phone had no internet connection at all — the web app now ships
  everything it needs locally instead of fetching a piece of it online.

## [2.0.0] - 2026-08-29

Full rewrite of the app on a server-authoritative architecture (one device
hosts and is the single source of truth, everyone else is a client over
LAN/WebSocket). First public release.

### Added

- Send money, collect from the bank, get paid for passing GO, or request
  money from another player.
- Buy properties, build houses/hotels, and pay auto-computed rent.
- Live auctions when a landing player declines to buy.
- A shared board view — no physical board needed.
- A shared dashboard for a TV or laptop at the table.
- NFC tap-to-pay for property cards (Android).
- Resilient sessions — reconnects and app restarts don't lose your seat or
  balance.
- A board editor to build and share your own boards.

## [1.0.0] - 2022-10-17

### Added

- Initial release: basic digital banking for Windows and Android.

[2.1.0]: https://github.com/georges-ph/digipoly/releases/tag/v2.1.0
[2.0.0]: https://github.com/georges-ph/digipoly/releases/tag/v2.0.0
[1.0.0]: https://github.com/georges-ph/digipoly/releases/tag/v1.0.0
