import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/injectors/service_locator.dart';
import '../screens/home_screen.dart';

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ServiceLocator.roomProvider),
      ],
      child: const MaterialApp(
        title: "Digipoly",
        debugShowCheckedModeBanner: false,
        home: HomeScreen(),
      ),
    );
  }
}
