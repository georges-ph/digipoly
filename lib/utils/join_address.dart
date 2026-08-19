import '../services/game_server.dart';

/// Parses a room address the user might type or scan: a bare IP
/// (optionally `:port`), or a full join link like
/// `http://192.168.1.24:47912/` (what the room QR and "copy link" encode).
({String host, int port})? parseJoinAddress(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
    final host = uri.queryParameters['host'] ?? uri.host;
    final port = int.tryParse(uri.queryParameters['port'] ?? '') ??
        (uri.hasPort ? uri.port : GameServer.defaultPort);
    return (host: host, port: port);
  }

  final parts = trimmed.split(':');
  final host = parts.first.trim();
  if (host.isEmpty) return null;
  final port = parts.length > 1
      ? int.tryParse(parts[1].trim())
      : GameServer.defaultPort;
  if (port == null) return null;
  return (host: host, port: port);
}
