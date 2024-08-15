
import 'package:digipoly/screens/home_screen.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
      title: "Digipoly",
      theme: ThemeData(
        visualDensity: VisualDensity.standard,
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
    );
  }
}
