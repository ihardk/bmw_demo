import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/note.dart';
import 'note_store.dart';

/// The saved notes, shared by every screen and by background scans.
class NotesRepository extends ChangeNotifier {
  NotesRepository(this._store);

  final NoteStore _store;
  List<Note> _notes = [];
  bool _loaded = false;

  List<Note> get notes => List.unmodifiable(_notes);
  bool get loaded => _loaded;

  Future<void> load() async {
    _notes = await _store.loadNotes();
    _loaded = true;
    notifyListeners();
  }

  Future<void> add(Note note) async {
    _notes.insert(0, note);
    notifyListeners();
    await _store.saveNotes(_notes);
  }

  /// Saves edits made to a note in place.
  Future<void> saveChanges() async {
    notifyListeners();
    await _store.saveNotes(_notes);
  }

  Future<void> delete(Note note) async {
    _notes.removeWhere((n) => n.id == note.id);
    notifyListeners();
    await _store.saveNotes(_notes);
    await deleteImages(note.imagePaths);
  }

  static Future<void> deleteImages(List<String> paths) async {
    for (final p in paths) {
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }
}
