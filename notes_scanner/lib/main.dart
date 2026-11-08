import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/local_model_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final model = LocalModelService.instance;
  runApp(NotesScannerApp(model: model));
  // Device check and engine start-up run while the first frame shows.
  await model.init();
}

class NotesScannerApp extends StatelessWidget {
  const NotesScannerApp({super.key, required this.model});
  final LocalModelService model;

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
      home: HomeScreen(model: model),
    );
  }
}
