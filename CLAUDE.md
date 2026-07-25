# Digipoly

Read @PROJECT.md for full context: what the app is, the game rules it
implements, the server-authoritative architecture, protocol, data model,
NFC/QR design, platform matrix and conventions.

Hard rules: no codegen/build_runner, no dartz (use Dart records via
`models/result.dart`), flat `lib/` structure, provider for state,
LAN-only (never depend on internet at runtime). Run `flutter analyze` and
`flutter test` after changes. Keep PROJECT.md updated when architecture or
rules change.
