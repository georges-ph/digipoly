import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/result.dart';
import '../providers/game_provider.dart';
import '../services/identity_service.dart';
import '../theme/app_theme.dart';
import 'game_screen.dart';
import 'home_screen.dart';

/// Landing screen when the web app is opened straight from a room — by
/// scanning the host's QR code or opening its join link directly. Asks for a
/// name and drops the player directly into the game, no menus.
class WebJoinScreen extends StatefulWidget {
  const WebJoinScreen({super.key, required this.host, required this.port});

  final String host;
  final int port;

  @override
  State<WebJoinScreen> createState() => _WebJoinScreenState();
}

class _WebJoinScreenState extends State<WebJoinScreen> {
  late final TextEditingController _nameController;
  bool _joining = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: context.read<IdentityService>().displayName,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _joining) return;

    setState(() {
      _joining = true;
      _error = null;
    });
    await context.read<IdentityService>().setDisplayName(name);
    if (!mounted) return;

    final result = await context
        .read<GameProvider>()
        .joinRoom(host: widget.host, port: widget.port);
    if (!mounted) return;

    if (result.isOk) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const GameScreen()),
      );
    } else {
      setState(() {
        _joining = false;
        _error = result.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: const BoxDecoration(
                      gradient: AppColors.heroGradient,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.casino_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Join the game',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Room at ${widget.host}:${widget.port}',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 24,
                  decoration: const InputDecoration(
                    labelText: 'Your name',
                    counterText: '',
                  ),
                  onSubmitted: (_) => _join(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _joining ? null : _join,
                  child: _joining
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Join'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall
                        ?.copyWith(color: AppColors.expense),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                  ),
                  child: const Text('Open the full app instead'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
