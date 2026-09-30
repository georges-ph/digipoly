# Contributing to Digipoly

Thanks for considering a contribution. Digipoly is a small, personal project,
but PRs and issues are welcome.

## Setup

```
flutter pub get
flutter run            # Windows or Android
```

To also test browser-based joining (the web build served by the host), see
"Bundling the web app" in the [README](README.md#bundling-the-web-app).

## Before submitting a change

```
flutter analyze
flutter test
```

Both must pass clean. If you touched the game rules or engine, add or update
a test in `test/game_engine_test.dart`.

## Conventions

- No code generation / `build_runner`.
- No `dartz` — errors use Dart records (`Result<T>` in
  `lib/models/result.dart`).
- Flat `lib/` structure (`models`, `services`, `providers`, `screens`,
  `widgets`, `theme`) — no feature folders or clean-architecture layers.
- State management via `provider`.
- LAN-only: nothing should depend on internet access at runtime.

See [PROJECT.md](PROJECT.md) for the full architecture, protocol, and game
rules reference before making a non-trivial change.

## Submitting a change

1. Fork the repo and create a branch off `main`.
2. Keep the change focused — one feature or fix per PR.
3. Make sure `flutter analyze` and `flutter test` pass.
4. Open a PR describing what changed and why, and which platforms you tested
   (Windows / Android / web).

## Reporting bugs / suggesting features

Open an issue using the bug report or feature request template. Include your
platform (Windows/Android/web) and Flutter version (`flutter --version`) for
bugs.
