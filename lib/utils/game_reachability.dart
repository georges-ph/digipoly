import 'game_reachability_stub.dart'
    if (dart.library.io) 'game_reachability_io.dart'
    if (dart.library.html) 'game_reachability_web.dart'
    as impl;

/// Confirms a specific game's host is actually still answering — used by
/// the games list to drive the "Live" badge on both native and web.
Future<bool> probeGameReachable(String host, int port, String gameId) =>
    impl.probeGameReachable(host, port, gameId);
