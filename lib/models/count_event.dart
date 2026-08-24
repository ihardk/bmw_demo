import 'dart:convert';

/// Which way a counter runs.
///
/// A single event flips from [until] to [since] on its own the moment the
/// target moment passes, so one event covers the whole life of a date.
enum CountDirection { until, since }

/// A single day counter: "128 Days Until December 31st" or "12 Days Since ...".
///
/// The counter always carries a [spanDays] window so it can be shown as a
/// fraction — a countdown walks 180/180 down to 1/180, a count-up walks
/// 1/180 up to 180/180 — plus a matching 0..1 progress value for the ring
/// and the bar.
class CountEvent {
  const CountEvent({
    required this.id,
    required this.title,
    required this.target,
    this.emoji = '',
    this.allDay = true,
    this.spanDays = 180,
    this.backgroundId = 'ember',
    this.imagePath,
  });

  final String id;
  final String title;

  /// The moment being counted to (or from).
  final DateTime target;

  /// Optional emoji shown next to the title.
  final String emoji;

  /// All-day events ignore the clock and count whole calendar days.
  final bool allDay;

  /// Length of the journey, in days — the denominator of `X / spanDays`.
  final int spanDays;

  /// Id of a built-in background preset (see `counter_backgrounds.dart`).
  final String backgroundId;

  /// Optional asset path that overrides [backgroundId] when set.
  final String? imagePath;

  CountEvent copyWith({
    String? title,
    DateTime? target,
    String? emoji,
    bool? allDay,
    int? spanDays,
    String? backgroundId,
    String? imagePath,
    bool clearImage = false,
  }) {
    return CountEvent(
      id: id,
      title: title ?? this.title,
      target: target ?? this.target,
      emoji: emoji ?? this.emoji,
      allDay: allDay ?? this.allDay,
      spanDays: spanDays ?? this.spanDays,
      backgroundId: backgroundId ?? this.backgroundId,
      imagePath: clearImage ? null : (imagePath ?? this.imagePath),
    );
  }

  // ---------------------------------------------------------------- counting

  static DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Whole calendar days between two moments, immune to DST shifts.
  ///
  /// The hours are rounded rather than truncated: a local day is 23 or 25
  /// hours long either side of a clock change, which would otherwise drop or
  /// add a day to the count.
  static int daysBetween(DateTime from, DateTime to) {
    final difference = _midnight(to).difference(_midnight(from));
    return (difference.inHours / 24).round();
  }

  /// The direction this event runs *right now*.
  CountDirection directionAt(DateTime now) {
    final passed =
        allDay ? daysBetween(now, target) < 0 : !target.isAfter(now);
    return passed ? CountDirection.since : CountDirection.until;
  }

  /// Days remaining (for an upcoming event) or days elapsed (for a past one).
  ///
  /// This is the big number on the card, and it is never negative: the day of
  /// the event itself reads `0`, the day after reads `1 Day Since`.
  int countAt(DateTime now) {
    final delta = daysBetween(now, target);
    return delta.abs();
  }

  /// How far along the journey is, as `0..1`.
  ///
  /// Counting down, the bar fills as the target approaches. Counting up, it
  /// fills as the days pile on after it.
  double progressAt(DateTime now) {
    if (spanDays <= 0) return 1;
    final travelled = travelledAt(now);
    final value = travelled / spanDays;
    return value.isNaN ? 0 : value.clamp(0.0, 1.0).toDouble();
  }

  /// Days already travelled through the [spanDays] window.
  int travelledAt(DateTime now) {
    final delta = daysBetween(now, target);
    final travelled =
        delta > 0 ? spanDays - delta /* counting down */ : -delta /* up */;
    return travelled.clamp(0, spanDays).toInt();
  }

  /// The numerator of the fraction shown under the counter.
  ///
  /// Countdown: `180/180 → 1/180`. Count-up: `1/180 → 180/180`.
  int fractionAt(DateTime now) {
    final delta = daysBetween(now, target);
    final value = delta > 0 ? delta : -delta;
    return value.clamp(0, spanDays).toInt();
  }

  /// `"128 / 180"` — the fraction line.
  String fractionLabelAt(DateTime now) => '${fractionAt(now)} / $spanDays';

  /// `"Days Until"` / `"Days Since"`, singular when the count is 1.
  String captionAt(DateTime now) {
    final unit = countAt(now) == 1 ? 'Day' : 'Days';
    return directionAt(now) == CountDirection.until
        ? '$unit Until'
        : '$unit Since';
  }

  /// Exact time left (or elapsed) — drives the live hh:mm:ss ticker.
  Duration remainderAt(DateTime now) {
    final anchor = allDay ? _midnight(target) : target;
    return anchor.difference(now).abs();
  }

  /// True on the day the event lands.
  bool isToday(DateTime now) => daysBetween(now, target) == 0;

  /// The day the journey started (countdown) — used by the editor's preview.
  DateTime get windowStart => _midnight(target).subtract(
        Duration(days: spanDays),
      );

  // ------------------------------------------------------------------- json

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'target': target.millisecondsSinceEpoch,
        'emoji': emoji,
        'allDay': allDay,
        'spanDays': spanDays,
        'backgroundId': backgroundId,
        'imagePath': imagePath,
      };

  factory CountEvent.fromJson(Map<String, dynamic> json) => CountEvent(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        target: DateTime.fromMillisecondsSinceEpoch(json['target'] as int),
        emoji: json['emoji'] as String? ?? '',
        allDay: json['allDay'] as bool? ?? true,
        spanDays: json['spanDays'] as int? ?? 180,
        backgroundId: json['backgroundId'] as String? ?? 'ember',
        imagePath: json['imagePath'] as String?,
      );

  static String encodeList(List<CountEvent> events) =>
      jsonEncode(events.map((e) => e.toJson()).toList());

  static List<CountEvent> decodeList(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(CountEvent.fromJson)
        .toList();
  }
}
