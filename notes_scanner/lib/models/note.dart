import 'dart:convert';

/// A note produced from one or more scanned notebook pages.
class Note {
  Note({
    required this.id,
    required this.title,
    required this.markdown,
    required this.createdAt,
    this.imagePaths = const [],
  });

  final String id;
  String title;
  String markdown;
  final DateTime createdAt;

  /// Local paths of the page photos the note was made from.
  final List<String> imagePaths;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'markdown': markdown,
    'createdAt': createdAt.toIso8601String(),
    'imagePaths': imagePaths,
  };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    id: json['id'] as String,
    title: json['title'] as String,
    markdown: json['markdown'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    imagePaths: (json['imagePaths'] as List?)?.cast<String>() ?? const [],
  );

  static String encodeList(List<Note> notes) =>
      jsonEncode(notes.map((n) => n.toJson()).toList());

  static List<Note> decodeList(String raw) => (jsonDecode(raw) as List)
      .map((e) => Note.fromJson(e as Map<String, dynamic>))
      .toList();
}
