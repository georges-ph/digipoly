import 'dart:convert';
import 'dart:io';

/// Not just "is something listening on host:port" — a bare TCP connect
/// would also succeed for a stale saved game whenever *any* room is
/// currently hosted from the same machine, since re-hosting always tries
/// the same default port first. Fetching the server's own game id and
/// comparing it against this record is what actually confirms it's still
/// this game answering there.
Future<bool> probeGameReachable(String host, int port, String gameId) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client
        .getUrl(Uri.http('$host:$port', '__digipoly_info'))
        .timeout(const Duration(seconds: 2));
    final response = await request.close().timeout(
      const Duration(seconds: 2),
    );
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 2));
    final json = jsonDecode(body) as Map<String, dynamic>;
    return json['gameId'] == gameId;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}
