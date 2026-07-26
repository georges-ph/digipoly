import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/identity_service.dart';
import '../widgets/name_sheet.dart';
import '../widgets/player_avatar.dart';
import 'boards_tab.dart';
import 'games_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;

  Future<void> _editProfile() async {
    await promptPlayerName(context, context.read<IdentityService>());
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final identity = context.read<IdentityService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('digipoly'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: InkWell(
              onTap: _editProfile,
              customBorder: const CircleBorder(),
              child: identity.hasName
                  ? CircleAvatar(
                      radius: 18,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHigh,
                      child: Text(
                        PlayerAvatar.initialsOf(identity.displayName),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    )
                  : CircleAvatar(
                      radius: 18,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHigh,
                      child: Icon(
                        Icons.person_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: const [GamesTab(), BoardsTab()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.sports_esports_outlined),
            selectedIcon: Icon(Icons.sports_esports),
            label: 'Games',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Boards',
          ),
        ],
      ),
    );
  }
}
