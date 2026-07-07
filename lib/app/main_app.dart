import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/injectors/service_locator.dart';
import '../features/room/presentation/screens/home_screen.dart';

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ServiceLocator.roomProvider),
      ],
      child: MaterialApp(
        title: "Digipoly",
        debugShowCheckedModeBanner: false,
        home: const HomeScreen(),
        darkTheme: ThemeData(brightness: .dark),
      ),
    );
  }
}
