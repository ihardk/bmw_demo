import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/background_keeper.dart';
import 'services/chat_engine.dart';
import 'services/local_model_service.dart';
import 'services/memory_monitor.dart';
import 'services/note_store.dart';
import 'services/notes_repository.dart';
import 'services/scan_pipeline.dart';
import 'services/scan_queue.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final model = LocalModelService.instance;
  final store = NoteStore();
  final notes = NotesRepository(store);
  final keeper = BackgroundKeeper()..init();
  final queue = ScanQueue(
    notes: notes,
    keeper: keeper,
    compareRunner: (pages, option, onProgress) =>
        ScanPipeline(model: model).scan(
          pages,
          mode: ReadingMode.best,
          option: option,
          fallbackToQuick: false,
          onProgress: onProgress,
        ),
    runner: (pages, mode, onProgress) =>
        ScanPipeline(model: model)
            .scan(pages, mode: mode, onProgress: onProgress),
  );
  runApp(
    NotesScannerApp(
      model: model,
      notes: notes,
      queue: queue,
      store: store,
      memory: MemoryMonitor(),
      chat: EdgeChatEngine(model),
    ),
  );
  // Loading notes and starting the engine run while the first frame shows.
  await Future.wait([notes.load(), model.init()]);
}

class NotesScannerApp extends StatelessWidget {
  const NotesScannerApp({
    super.key,
    required this.model,
    required this.notes,
    required this.queue,
    required this.store,
    required this.memory,
    required this.chat,
  });

  final LocalModelService model;
  final NotesRepository notes;
  final ScanQueue queue;
  final NoteStore store;
  final MemoryMonitor memory;
  final ChatEngine chat;

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
      home: HomeScreen(
        model: model,
        notes: notes,
        queue: queue,
        store: store,
        memory: memory,
        chat: chat,
      ),
    );
  }
}
