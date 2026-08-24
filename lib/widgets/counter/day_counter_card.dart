import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../constants/counter_backgrounds.dart';
import '../../constants/my_colors.dart';
import '../../models/count_event.dart';
import 'counter_background.dart';
import 'counter_progress.dart';

/// Formats `December 31st 2026`.
String formatEventDate(DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.day}${_ordinal(date.day)} '
      '${date.year}';
}

String _ordinal(int day) {
  if (day >= 11 && day <= 13) return 'th';
  switch (day % 10) {
    case 1:
      return 'st';
    case 2:
      return 'nd';
    case 3:
      return 'rd';
    default:
      return 'th';
  }
}

/// The counter card used across the app and captured for the home-screen
/// widget.
///
/// Everything on it is derived from [now], so a single ticker higher up keeps
/// every card on screen in step.
class DayCounterCard extends StatelessWidget {
  const DayCounterCard({
    super.key,
    required this.event,
    required this.now,
    this.onTap,
    this.onLongPress,
    this.height = 190,
    this.compact = false,
  });

  final CountEvent event;
  final DateTime now;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double height;

  /// Drops the progress footer — used for the small widget preview.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final background = backgroundById(event.backgroundId);
    final count = event.countAt(now);
    final isToday = event.isToday(now);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.45),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: CounterBackgroundView(
            background: background,
            imagePath: event.imagePath,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(event: event, isToday: isToday),
                  const Spacer(),
                  _CountLine(
                    count: count,
                    caption: event.captionAt(now),
                    isToday: isToday,
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 14),
                    _Footer(event: event, now: now),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.event, required this.isToday});

  final CountEvent event;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (event.emoji.isNotEmpty) ...[
          Text(event.emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            event.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: kcWhite,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              shadows: [
                Shadow(color: Colors.black54, blurRadius: 8),
              ],
            ),
          ),
        ),
        if (isToday) const SizedBox(width: 8),
        if (isToday) const _TodayPill(),
      ],
    );
  }
}

class _TodayPill extends StatelessWidget {
  const _TodayPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: kcWhite,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'TODAY',
        style: TextStyle(
          color: Colors.black,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _CountLine extends StatelessWidget {
  const _CountLine({
    required this.count,
    required this.caption,
    required this.isToday,
  });

  final int count;
  final String caption;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          isToday ? 'Today' : '$count',
          style: TextStyle(
            color: kcWhite,
            fontSize: isToday ? 46 : 62,
            height: 0.95,
            fontWeight: FontWeight.w300,
            fontFeatures: const [FontFeature.tabularFigures()],
            shadows: const [
              Shadow(color: Colors.black45, blurRadius: 16),
            ],
          ),
        ),
        if (!isToday) ...[
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              caption.toUpperCase(),
              style: const TextStyle(
                color: Color(0xE6FFFFFF),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
                shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.event, required this.now});

  final CountEvent event;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CounterProgressBar(progress: event.progressAt(now)),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              event.fractionLabelAt(now),
              style: const TextStyle(
                color: Color(0xCCFFFFFF),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                formatEventDate(event.target),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xCCFFFFFF),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
