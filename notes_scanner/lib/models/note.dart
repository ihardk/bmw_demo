import 'dart:convert';

/// What one model made of a note's pages, kept for comparison.
class NoteVersion {
  NoteVersion({
    required this.modelId,
    required this.modelName,
    required this.createdAt,
    this.markdown = '',
    this.error,
    this.totalMs,
    this.modelLoadMs,
    this.firstTokenMs,
    this.tokensPerSec,
    this.words,
    this.backend,
    this.peakRamMb,
    this.pageTimesMs = const [],
  });

  final String modelId;
  final String modelName;
  final DateTime createdAt;
  final String markdown;

  /// Set when the model failed; [markdown] is then empty.
  final String? error;
  final int? totalMs;
  final int? modelLoadMs;
  final int? firstTokenMs;
  final double? tokensPerSec;
  final int? words;
  final String? backend;

  /// This app's highest memory use while the model ran.
  final int? peakRamMb;
  final List<int> pageTimesMs;

  bool get failed => error != null;

  Map<String, dynamic> toJson() => {
    'modelId': modelId,
    'modelName': modelName,
    'createdAt': createdAt.toIso8601String(),
    'markdown': markdown,
    'error': ?error,
    'totalMs': ?totalMs,
    'modelLoadMs': ?modelLoadMs,
    'firstTokenMs': ?firstTokenMs,
    'tokensPerSec': ?tokensPerSec,
    'words': ?words,
    'backend': ?backend,
    'peakRamMb': ?peakRamMb,
    'pageTimesMs': pageTimesMs,
  };

  factory NoteVersion.fromJson(Map<String, dynamic> j) => NoteVersion(
    modelId: j['modelId'] as String,
    modelName: j['modelName'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    markdown: j['markdown'] as String? ?? '',
    error: j['error'] as String?,
    totalMs: j['totalMs'] as int?,
    modelLoadMs: j['modelLoadMs'] as int?,
    firstTokenMs: j['firstTokenMs'] as int?,
    tokensPerSec: (j['tokensPerSec'] as num?)?.toDouble(),
    words: j['words'] as int?,
    backend: j['backend'] as String?,
    peakRamMb: j['peakRamMb'] as int?,
    pageTimesMs: (j['pageTimesMs'] as List?)?.cast<int>() ?? const [],
  );
}

/// A note produced from one or more scanned notebook pages.
class Note {
  Note({
    required this.id,
    required this.title,
    required this.markdown,
    required this.createdAt,
    this.imagePaths = const [],
    this.engine,
    List<NoteVersion>? versions,
  }) : versions = versions ?? [];

  final String id;
  String title;
  String markdown;
  final DateTime createdAt;

  /// Local paths of the page photos the note was made from.
  final List<String> imagePaths;

  /// Which reader produced the note text (on-device model or quick scan).
  String? engine;

  /// Other models' readings of the same pages, newest first.
  final List<NoteVersion> versions;

  /// Makes [v] the note's text. The text it replaces is kept as a version,
  /// so nothing is lost.
  void useVersion(NoteVersion v, {required String title}) {
    versions.insert(
      0,
      NoteVersion(
        modelId: 'earlier',
        modelName: 'Earlier note text${engine != null ? ' ($engine)' : ''}',
        createdAt: DateTime.now(),
        markdown: markdown,
      ),
    );
    markdown = v.markdown;
    this.title = title;
    engine = 'On-device AI (${v.modelName})';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'markdown': markdown,
    'createdAt': createdAt.toIso8601String(),
    'imagePaths': imagePaths,
    'engine': ?engine,
    if (versions.isNotEmpty)
      'versions': versions.map((v) => v.toJson()).toList(),
  };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    id: json['id'] as String,
    title: json['title'] as String,
    markdown: json['markdown'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    imagePaths: (json['imagePaths'] as List?)?.cast<String>() ?? const [],
    engine: json['engine'] as String?,
    versions: (json['versions'] as List?)
        ?.map((v) => NoteVersion.fromJson(v as Map<String, dynamic>))
        .toList(),
  );

  static String encodeList(List<Note> notes) =>
      jsonEncode(notes.map((n) => n.toJson()).toList());

  static List<Note> decodeList(String raw) => (jsonDecode(raw) as List)
      .map((e) => Note.fromJson(e as Map<String, dynamic>))
      .toList();
}
