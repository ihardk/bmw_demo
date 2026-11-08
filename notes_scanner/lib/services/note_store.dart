import 'package:shared_preferences/shared_preferences.dart';

import '../models/note.dart';

/// Persists notes and the API key on the device.
class NoteStore {
  static const _notesKey = 'notes';
  static const _apiKeyKey = 'anthropic_api_key';

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

  Future<String?> loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_apiKeyKey);
    return (key == null || key.isEmpty) ? null : key;
  }

  Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey, key.trim());
  }
}
