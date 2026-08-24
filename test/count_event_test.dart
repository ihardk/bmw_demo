import 'package:bmw_demo/models/count_event.dart';
import 'package:flutter_test/flutter_test.dart';

CountEvent eventAt(DateTime target, {int spanDays = 180}) => CountEvent(
      id: 'test',
      title: 'Test',
      target: target,
      spanDays: spanDays,
    );

void main() {
  final now = DateTime(2026, 8, 24, 13, 30);

  group('counting down', () {
    test('starts the window at spanDays / spanDays', () {
      final event = eventAt(now.add(const Duration(days: 180)));
      expect(event.fractionLabelAt(now), '180 / 180');
      expect(event.progressAt(now), 0);
      expect(event.captionAt(now), 'Days Until');
    });

    test('reaches 1 / spanDays the day before', () {
      final event = eventAt(now.add(const Duration(days: 1)));
      expect(event.fractionLabelAt(now), '1 / 180');
      expect(event.countAt(now), 1);
      expect(event.captionAt(now), 'Day Until');
      expect(event.progressAt(now), closeTo(179 / 180, 0.0001));
    });

    test('clamps a target beyond the window', () {
      final event = eventAt(now.add(const Duration(days: 400)));
      expect(event.fractionLabelAt(now), '180 / 180');
      expect(event.progressAt(now), 0);
      expect(event.countAt(now), 400);
    });
  });

  group('counting up', () {
    test('reads 1 / spanDays the day after', () {
      final event = eventAt(now.subtract(const Duration(days: 1)));
      expect(event.fractionLabelAt(now), '1 / 180');
      expect(event.captionAt(now), 'Day Since');
      expect(event.directionAt(now), CountDirection.since);
      expect(event.progressAt(now), closeTo(1 / 180, 0.0001));
    });

    test('fills the window at spanDays / spanDays', () {
      final event = eventAt(now.subtract(const Duration(days: 180)));
      expect(event.fractionLabelAt(now), '180 / 180');
      expect(event.progressAt(now), 1);
    });
  });

  group('the day itself', () {
    test('is neither until nor since once the clock passes', () {
      final event = eventAt(DateTime(2026, 8, 24, 9));
      expect(event.isToday(now), isTrue);
      expect(event.countAt(now), 0);
    });

    test('counts whole days, ignoring the time of day, when all-day', () {
      final event = CountEvent(
        id: 'test',
        title: 'Test',
        target: DateTime(2026, 8, 25, 1),
      );
      expect(event.countAt(now), 1);
      expect(event.directionAt(now), CountDirection.until);
    });

    test('a timed event flips as soon as its moment passes', () {
      final event = CountEvent(
        id: 'test',
        title: 'Test',
        allDay: false,
        target: DateTime(2026, 8, 24, 12),
      );
      expect(event.directionAt(now), CountDirection.since);
    });
  });

  test('survives a round trip through json', () {
    final event = CountEvent(
      id: 'abc',
      title: 'Launch',
      emoji: '🚀',
      target: DateTime(2026, 12, 31),
      spanDays: 90,
      backgroundId: 'gold',
    );
    final restored = CountEvent.decodeList(CountEvent.encodeList([event])).single;

    expect(restored.id, event.id);
    expect(restored.title, event.title);
    expect(restored.emoji, event.emoji);
    expect(restored.target, event.target);
    expect(restored.spanDays, event.spanDays);
    expect(restored.backgroundId, event.backgroundId);
  });
}
