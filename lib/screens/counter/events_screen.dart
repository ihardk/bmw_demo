import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../constants/my_colors.dart';
import '../../data/event_store.dart';
import '../../models/count_event.dart';
import '../../widgets/background_container.dart';
import '../../widgets/counter/counter_progress.dart';
import '../../widgets/counter/day_counter_card.dart';
import 'event_detail_screen.dart';
import 'event_editor_screen.dart';

/// The counter list: every tracked date, upcoming ones first.
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final EventStore _store = EventStore.instance;
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
    _store.load();
    // One ticker for the whole list keeps every card in step, and catches the
    // midnight roll-over that flips "Days Until" into "Days Since".
    _ticker = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openEditor({CountEvent? event}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EventEditorScreen(event: event)),
    );
  }

  Future<void> _openDetail(CountEvent event) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EventDetailScreen(eventId: event.id)),
    );
  }

  Future<void> _delete(CountEvent event) async {
    await _store.remove(event.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: kcBGGrey,
          content: Text('"${event.title}" removed'),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: kcSecondaryEnd,
            onPressed: () => _store.add(event),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final events = _store.events;

    return Scaffold(
      extendBody: true,
      body: BackgroundContainer(
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(now: _now, count: events.length),
              Expanded(
                child: events.isEmpty
                    ? _EmptyState(onCreate: () => _openEditor())
                    : _buildList(events),
              ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _NewCounterButton(onTap: () => _openEditor()),
    );
  }

  Widget _buildList(List<CountEvent> events) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      itemCount: events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 18),
      itemBuilder: (context, index) {
        final event = events[index];
        return Dismissible(
          key: ValueKey(event.id),
          direction: DismissDirection.endToStart,
          background: const _DeleteBackground(),
          onDismissed: (_) => _delete(event),
          child: DayCounterCard(
            event: event,
            now: _now,
            onTap: () => _openDetail(event),
            onLongPress: () => _openEditor(event: event),
          ),
        )
            .animate()
            .fadeIn(
              duration: const Duration(milliseconds: 350),
              delay: Duration(milliseconds: 60 * index),
            )
            .slideY(
              begin: 0.12,
              end: 0,
              duration: const Duration(milliseconds: 400),
              delay: Duration(milliseconds: 60 * index),
              curve: Curves.easeOutCubic,
            );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.now, required this.count});

  final DateTime now;
  final int count;

  static const _weekdays = [
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
    'SATURDAY',
    'SUNDAY',
  ];

  @override
  Widget build(BuildContext context) {
    final date = formatEventDate(now).split(' ');
    final today = '${_weekdays[now.weekday - 1]}, '
        '${date.first.toUpperCase()} ${now.day}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            today,
            style: const TextStyle(
              color: kcLabelGreyLight,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Countdowns',
                style: TextStyle(
                  color: kcWhite,
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 10),
              if (count > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: kcBGGrey,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$count tracked',
                      style: const TextStyle(
                        color: kcSecondaryEnd,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: const Duration(milliseconds: 400));
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 28),
      decoration: BoxDecoration(
        color: kcSecondaryDark,
        borderRadius: BorderRadius.circular(26),
      ),
      child: const Icon(Icons.delete_outline_rounded, color: kcWhite),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CounterProgressRing(
              progress: 0.35,
              size: 120,
              child: Icon(
                Icons.hourglass_empty_rounded,
                color: kcSecondaryEnd,
                size: 34,
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Nothing on the clock',
              style: TextStyle(
                color: kcWhite,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Add a date and watch it count down — or count up once it '
              'has passed.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kcLabelGreyLight, fontSize: 14),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: onCreate,
              child: const Text(
                'Create your first counter',
                style: TextStyle(color: kcSecondaryEnd),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: const Duration(milliseconds: 500));
  }
}

class _NewCounterButton extends StatelessWidget {
  const _NewCounterButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
            gradient: const LinearGradient(
              colors: [kcSecondaryStart, kcSecondaryEnd],
            ),
            boxShadow: [
              BoxShadow(
                color: kcSecondaryStart.withOpacity(0.45),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, color: kcWhite, size: 20),
              SizedBox(width: 8),
              Text(
                'New Counter',
                style: TextStyle(
                  color: kcWhite,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
