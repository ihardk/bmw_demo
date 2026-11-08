import 'package:shared_preferences/shared_preferences.dart';

import '../models/note.dart';
import 'scan_pipeline.dart';

/// Persists notes and settings on the device.
class NoteStore {
  static const _notesKey = 'notes';
  static const _modeKey = 'reading_mode';
  static const _bannerKey = 'model_banner_dismissed';

  Future<List<Note>> loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_notesKey);
    if (raw == null || raw.isEmpty) return [];
    final notes = Note.decodeList(raw);
    notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return notes;
  }

  Future<void> saveNotes(List<Note> notes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_notesKey, Note.encodeList(notes));
  }

  Future<ReadingMode> loadMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_modeKey) == 'quick'
        ? ReadingMode.quick
        : ReadingMode.best;
  }

  Future<void> saveMode(ReadingMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
  }

  Future<bool> bannerDismissed() async =>
      (await SharedPreferences.getInstance()).getBool(_bannerKey) ?? false;

  Future<void> dismissBanner() async =>
      (await SharedPreferences.getInstance()).setBool(_bannerKey, true);
}
