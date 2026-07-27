import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/result.dart';
import '../providers/game_provider.dart';
import '../services/discovery_service.dart';
import '../services/game_server.dart';
import '../theme/app_theme.dart';
import '../utils/snack.dart';
import '../widgets/section_header.dart';
import 'dashboard_screen.dart';
import 'game_screen.dart';

/// Rooms discovered on the local network via mDNS, plus a manual
/// address fallback for networks that block multicast.
class JoinGameScreen extends StatefulWidget {
  const JoinGameScreen({super.key, this.spectator = false});

  /// Watch the dashboard read-only instead of joining as a player — no
  /// seat, no name needed, nothing saved to this device's games list.
  final bool spectator;

  @override
  State<JoinGameScreen> createState() => _JoinGameScreenState();
}

class _JoinGameScreenState extends State<JoinGameScreen> {
  final _addressController = TextEditingController();
  String? _joiningKey;
  late final DiscoveryService _discovery;

  @override
  void initState() {
    super.initState();
    _discovery = context.read<DiscoveryService>();
    _discovery.startDiscovery();
  }

  @override
  void dispose() {
    _discovery.stopDiscovery();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _join(String host, int port, String key) async {
    if (_joiningKey != null) return;
    final session = context.read<GameProvider>();
    setState(() => _joiningKey = key);

    final result = widget.spectator
        ? await session.watchRoom(host: host, port: port)
        : await session.joinRoom(host: host, port: port);
    if (!mounted) return;
    setState(() => _joiningKey = null);

    if (result.isOk) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              widget.spectator ? const DashboardScreen() : const GameScreen(),
        ),
      );
    } else {
      showSnack(context, result.error!);
    }
  }

  void _joinManual() {
    final text = _addressController.text.trim();
    if (text.isEmpty) return;

    String host;
    int? port;
    final uri = Uri.tryParse(text);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      // A pasted join link: http://<ip>:<port>/
      host = uri.queryParameters['host'] ?? uri.host;
      port = int.tryParse(uri.queryParameters['port'] ?? '') ??
          (uri.hasPort ? uri.port : GameServer.defaultPort);
    } else {
      final parts = text.split(':');
      host = parts.first.trim();
      port = parts.length > 1
          ? int.tryParse(parts[1].trim())
          : GameServer.defaultPort;
    }
    if (host.isEmpty || port == null) {
      showSnack(
          context,
          'Enter an address like 192.168.1.24, or paste '
          'the join link.');
      return;
    }
    _join(host, port, 'manual');
  }

  @override
  Widget build(BuildContext context) {
    final discovery = context.read<DiscoveryService>();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.spectator ? 'Watch a game' : 'Join a game'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addressController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Host address',
                      hintText: '192.168.1.24 or a join link',
                    ),
                    onSubmitted: (_) => _joinManual(),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed:
                        _joiningKey == null ? _joinManual : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(64, 56),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    child: _joiningKey == 'manual'
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Join'),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: SectionHeader(
              title: 'Rooms on your network',
              trailing: kIsWeb
                  ? null
                  : SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<DiscoveredRoom>>(
              stream: discovery.rooms,
              initialData: discovery.currentRooms,
              builder: (context, snapshot) {
                final rooms = snapshot.data ?? const <DiscoveredRoom>[];
                if (rooms.isEmpty) {
                  // Centered in the free space, whatever the window size.
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wifi_tethering_rounded,
                          size: 44,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          kIsWeb
                              ? 'Discovery is not available in the browser'
                              : 'Searching for rooms…',
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          kIsWeb
                              ? 'Ask the host for the room address and type '
                                  'it above to join.'
                              : 'Make sure you are on the same wifi as the '
                                  'host. If nothing shows up, ask the host '
                                  'for the room address and type it above.',
                          textAlign: TextAlign.center,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                        ),
                      ),
                    ),
                  );
                }
                // Cards cap at ~520px and wrap into columns, so a wide
                // window shows rooms side by side instead of stretching
                // one card across the whole screen.
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 520,
                    mainAxisExtent: 88,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemCount: rooms.length,
                  itemBuilder: (context, index) {
                    final room = rooms[index];
                    final color = AppColors.avatarColor(
                      room.gameId.isEmpty ? room.serviceName : room.gameId,
                    );
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radius),
                        ),
                        leading: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.casino_rounded, color: color),
                        ),
                        title: Text(
                          room.gameName,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(
                          [
                            if (room.boardName.isNotEmpty) room.boardName,
                            '${room.host}:${room.port}',
                          ].join(' · '),
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: _joiningKey == room.serviceName
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.chevron_right_rounded),
                        onTap: () =>
                            _join(room.host, room.port, room.serviceName),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
