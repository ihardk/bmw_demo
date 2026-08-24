import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../constants/my_colors.dart';
import '../../utils/circular_arc_calculations.dart';

/// A slim ring that shows how far a counter has travelled through its window.
///
/// The track is drawn full-circle, the value arc sweeps clockwise from the top
/// and ends in a small cap so the exact position stays readable even at a
/// couple of percent.
class CounterProgressRing extends StatelessWidget {
  const CounterProgressRing({
    super.key,
    required this.progress,
    this.size = 148,
    this.strokeWidth = 8,
    this.colors = const [kcSecondaryStart, kcSecondaryEnd],
    this.trackColor = const Color(0x33FFFFFF),
    this.child,
  });

  final double progress;
  final double size;
  final double strokeWidth;
  final List<Color> colors;
  final Color trackColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      width: size,
      child: CustomPaint(
        painter: _RingPainter(
          progress: progress.clamp(0.0, 1.0).toDouble(),
          strokeWidth: strokeWidth,
          colors: colors,
          trackColor: trackColor,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.colors,
    required this.trackColor,
  });

  final double progress;
  final double strokeWidth;
  final List<Color> colors;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const startAngle = -math.pi / 2;
    final sweep = fullAngleInRadians * progress;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = trackColor,
    );

    if (progress <= 0) return;

    canvas.drawArc(
      rect,
      startAngle,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: fullAngleInRadians,
          colors: [...colors, colors.first],
          transform: const GradientRotation(startAngle),
        ).createShader(rect),
    );

    // Cap marking the live position.
    final head = toPolar(center, startAngle + sweep, radius);
    canvas.drawCircle(
      head,
      strokeWidth * 0.42,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.colors != colors ||
      oldDelegate.strokeWidth != strokeWidth;
}

/// A rounded progress bar with the same gradient language as the ring.
class CounterProgressBar extends StatelessWidget {
  const CounterProgressBar({
    super.key,
    required this.progress,
    this.height = 6,
    this.colors = const [kcSecondaryStart, kcSecondaryEnd],
    this.trackColor = const Color(0x33FFFFFF),
  });

  final double progress;
  final double height;
  final List<Color> colors;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: trackColor),
              child: const SizedBox.expand(),
            ),
            FractionallySizedBox(
              widthFactor: value == 0 ? 0.0001 : value,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors),
                  borderRadius: BorderRadius.circular(height),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
