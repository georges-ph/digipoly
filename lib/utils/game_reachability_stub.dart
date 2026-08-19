/// Fallback for a platform that's neither dart:io nor dart:html capable —
/// shouldn't be reachable on any platform Flutter actually targets.
Future<bool> probeGameReachable(String host, int port, String gameId) async =>
    false;
