import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() => runApp(const NotesScannerApp());

class NotesScannerApp extends StatelessWidget {
  const NotesScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3F51B5);
    return MaterialApp(
      title: 'Notes Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
