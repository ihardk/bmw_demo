import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../constants/counter_backgrounds.dart';
import '../../constants/my_colors.dart';
import '../../data/day_counter_bridge.dart';
import '../../data/event_store.dart';
import '../../models/count_event.dart';
import '../../widgets/counter/counter_background.dart';
import '../../widgets/counter/counter_progress.dart';
import '../../widgets/counter/day_counter_card.dart';
import 'event_editor_screen.dart';

/// One counter, full screen: the ring, the exact remainder down to the second,
/// and the button that puts it on the home screen.
class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({super.key, required this.eventId});

  final String eventId;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  final GlobalKey _artworkKey = GlobalKey();
  final EventStore _store = EventStore.instance;

  Timer? _ticker;
  DateTime _now = DateTime.now();
  bool _pinning = false;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
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

  /// Grabs the artwork behind the counter as a PNG so the Android widget can
  /// show the very same background while drawing its own live numbers.
  Future<Uint8List?> _captureArtwork() async {
    final context = _artworkKey.currentContext;
    if (context == null) return null;
    final boundary = context.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  Future<void> _pinToHomeScreen(CountEvent event) async {
    setState(() => _pinning = true);
    final artwork = await _captureArtwork();
    final stored = await DayCounterBridge.pinEvent(event, artwork: artwork);
    final requested = stored
        ? await DayCounterBridge.requestPinToHomeScreen(event)
        : false;
    if (!mounted) return;
    setState(() => _pinning = false);

    final message = !stored
        ? 'Home-screen widgets need the Android build of this app.'
        : requested
            ? 'Sent to your home screen.'
            : 'Widget updated — drop the "Day Counter" widget on your home '
                'screen to see it.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(backgroundColor: kcBGGrey, content: Text(message)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final event = _store.byId(widget.eventId);
    if (event == null) {
      // The counter was deleted from underneath us (undo, or the editor).
      return const Scaffold(backgroundColor: kcBGDark);
    }

    final background = backgroundById(event.backgroundId);
    final isToday = event.isToday(_now);

    return Scaffold(
      backgroundColor: kcBGDark,
      body: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            key: _artworkKey,
            child: CounterBackgroundView(
              background: background,
              imagePath: event.imagePath,
              scrim: 0.7,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(event),
                const Spacer(),
                _buildCounter(event, isToday),
                const SizedBox(height: 28),
                _buildRemainder(event, isToday),
                const Spacer(),
                _buildStats(event),
                const SizedBox(height: 20),
                _buildPinButton(event),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(CountEvent event) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: kcWhite),
          ),
          Expanded(
            child: Text(
              event.emoji.isEmpty ? event.title : '${event.emoji}  ${event.title}',
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: kcWhite,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EventEditorScreen(event: event),
              ),
            ),
            icon: const Icon(Icons.tune_rounded, color: kcWhite),
          ),
        ],
      ),
    );
  }

  Widget _buildCounter(CountEvent event, bool isToday) {
    return CounterProgressRing(
      progress: event.progressAt(_now),
      size: 260,
      strokeWidth: 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isToday ? 'Today' : '${event.countAt(_now)}',
            style: TextStyle(
              color: kcWhite,
              fontSize: isToday ? 56 : 84,
              height: 1,
              fontWeight: FontWeight.w200,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            event.captionAt(_now).toUpperCase(),
            style: const TextStyle(
              color: Color(0xE6FFFFFF),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: const Duration(milliseconds: 400)).scaleXY(
          begin: 0.92,
          end: 1,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutBack,
        );
  }

  Widget _buildRemainder(CountEvent event, bool isToday) {
    final remainder = event.remainderAt(_now);
    final hours = remainder.inHours % 24;
    final minutes = remainder.inMinutes % 60;
    final seconds = remainder.inSeconds % 60;

    return Column(
      children: [
        Text(
          formatEventDate(event.target),
          style: const TextStyle(
            color: kcWhite,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${_two(hours)}:${_two(minutes)}:${_two(seconds)}',
          style: const TextStyle(
            color: Color(0x99FFFFFF),
            fontSize: 14,
            letterSpacing: 3,
            fontFeatures: [ui.FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _buildStats(CountEvent event) {
    final travelled = event.travelledAt(_now);
    final remaining = event.spanDays - travelled;
    final percent = (event.progressAt(_now) * 100).round();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.35),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          children: [
            Row(
              children: [
                _Stat(label: 'COUNT', value: event.fractionLabelAt(_now)),
                _Stat(label: 'ELAPSED', value: '$travelled d'),
                _Stat(label: 'LEFT', value: '$remaining d'),
                _Stat(label: 'PROGRESS', value: '$percent%'),
              ],
            ),
            const SizedBox(height: 16),
            CounterProgressBar(progress: event.progressAt(_now), height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildPinButton(CountEvent event) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        height: 54,
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _pinning ? null : () => _pinToHomeScreen(event),
          style: ElevatedButton.styleFrom(
            backgroundColor: kcWhite,
            foregroundColor: Colors.black,
            disabledBackgroundColor: kcBGGrey,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(27),
            ),
          ),
          icon: _pinning
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.widgets_rounded, size: 20),
          label: Text(
            _pinning ? 'Preparing…' : 'Add to home screen',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

String _two(int value) => value.toString().padLeft(2, '0');

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: kcWhite,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFeatures: [ui.FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0x8CFFFFFF),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
