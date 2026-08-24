import 'package:flutter/foundation.dart';

import '../constants/counter_backgrounds.dart';
import '../models/count_event.dart';
import 'day_counter_bridge.dart';

/// The single source of truth for counters.
///
/// Events live in memory and are mirrored to the Android host (see
/// [DayCounterBridge]) so they survive a restart. Where no host is available
/// the seed list below is what the app starts with.
class EventStore extends ChangeNotifier {
  EventStore._();

  static final EventStore instance = EventStore._();

  final List<CountEvent> _events = [];
  bool _loaded = false;

  List<CountEvent> get events => List.unmodifiable(_events);
  bool get isLoaded => _loaded;
  bool get isEmpty => _loaded && _events.isEmpty;

  /// Loads persisted events once per app launch, falling back to the seeds.
  Future<void> load() async {
    if (_loaded) return;
    final stored = await DayCounterBridge.loadEvents();
    _events
      ..clear()
      ..addAll(stored ?? _seed());
    _loaded = true;
    _sort();
    notifyListeners();
  }

  Future<void> add(CountEvent event) async {
    _events.add(event);
    _sort();
    notifyListeners();
    await _persist();
  }

  Future<void> update(CountEvent event) async {
    final index = _events.indexWhere((e) => e.id == event.id);
    if (index == -1) return;
    _events[index] = event;
    _sort();
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String id) async {
    _events.removeWhere((e) => e.id == id);
    notifyListeners();
    await _persist();
  }

  CountEvent? byId(String id) {
    for (final event in _events) {
      if (event.id == id) return event;
    }
    return null;
  }

  /// Upcoming events first, nearest to today at the top, past events after.
  void _sort() {
    final now = DateTime.now();
    _events.sort((a, b) {
      final aUpcoming = a.directionAt(now) == CountDirection.until;
      final bUpcoming = b.directionAt(now) == CountDirection.until;
      if (aUpcoming != bUpcoming) return aUpcoming ? -1 : 1;
      return aUpcoming
          ? a.target.compareTo(b.target)
          : b.target.compareTo(a.target);
    });
  }

  Future<void> _persist() => DayCounterBridge.saveEvents(_events);

  static String newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  /// First-run content, so the list is never an empty rectangle.
  List<CountEvent> _seed() {
    final now = DateTime.now();
    return [
      CountEvent(
        id: 'seed-launch',
        title: 'Concept i4 Launch',
        emoji: '⚡',
        target: DateTime(now.year, 12, 31),
        spanDays: 180,
        backgroundId: kBackgroundConcept.id,
      ),
      CountEvent(
        id: 'seed-delivery',
        title: 'Delivery Day',
        emoji: '🔑',
        target: DateTime(now.year, now.month, now.day)
            .add(const Duration(days: 42)),
        spanDays: 180,
        backgroundId: kBackgroundGold.id,
      ),
      CountEvent(
        id: 'seed-since',
        title: 'Test Drive',
        emoji: '🏁',
        target: DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 26)),
        spanDays: 180,
        backgroundId: kBackgroundMidnight.id,
      ),
    ];
  }
}
