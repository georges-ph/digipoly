import 'dart:convert';
import 'dart:html' as html;

/// dart:io's HttpClient/Socket don't work on web — this is the browser-side
/// equivalent, hitting the same `__digipoly_info` endpoint via XHR. A
/// same-origin request (the common case: this web app was opened by
/// scanning/visiting the very room it's now checking) needs no server-side
/// cooperation; a cross-origin one relies on the server's permissive CORS
/// header on that one endpoint (see game_server.dart's `_serveWebApp`).
Future<bool> probeGameReachable(String host, int port, String gameId) async {
  try {
    final response = await html.HttpRequest.request(
      'http://$host:$port/__digipoly_info',
    ).timeout(const Duration(seconds: 2));
    final body = response.responseText;
    if (body == null) return false;
    final json = jsonDecode(body) as Map<String, dynamic>;
    return json['gameId'] == gameId;
  } catch (_) {
    return false;
  }
}
