import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/boards_provider.dart';
import 'providers/game_provider.dart';
import 'providers/games_provider.dart';
import 'screens/home_screen.dart';
import 'screens/web_join_screen.dart';
import 'services/database_service.dart';
import 'services/discovery_service.dart';
import 'services/identity_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final database = DatabaseService();
  await database.init();

  final identity = IdentityService();
  await identity.init();

  final discovery = DiscoveryService();

  runApp(
    DigipolyApp(
      database: database,
      identity: identity,
      discovery: discovery,
    ),
  );
}

class DigipolyApp extends StatelessWidget {
  const DigipolyApp({
    super.key,
    required this.database,
    required this.identity,
    required this.discovery,
  });

  final DatabaseService database;
  final IdentityService identity;
  final DiscoveryService discovery;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<DatabaseService>.value(value: database),
        Provider<IdentityService>.value(value: identity),
        Provider<DiscoveryService>.value(value: discovery),
        ChangeNotifierProvider(
          create: (_) => BoardsProvider(database)..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => GamesProvider(database)..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => GameProvider(
            database: database,
            identity: identity,
            discovery: discovery,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Digipoly',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: _initialScreen(),
      ),
    );
  }

  /// On the web, a QR scan or shared link lands players straight in the
  /// room: a page served by the game server itself (plain http on a LAN
  /// address) implies its own host and port from the URL itself.
  Widget _initialScreen() {
    if (!kIsWeb) return const HomeScreen();

    final base = Uri.base;
    final servedFromRoom = base.scheme == 'http' && base.host.isNotEmpty && base.host != 'localhost' && base.host != '127.0.0.1' && base.hasPort;
    if (servedFromRoom) {
      return WebJoinScreen(host: base.host, port: base.port);
    }
    return const HomeScreen();
  }
}
