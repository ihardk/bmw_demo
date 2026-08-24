import 'package:flutter/material.dart';

import '../../constants/counter_backgrounds.dart';

/// Paints a counter background: optional photo, gradient, accent bloom and a
/// legibility scrim, in that order.
///
/// The scrim is what keeps the big number readable no matter how busy the
/// picture behind it is — the reference design let bright artwork run straight
/// under the digits.
class CounterBackgroundView extends StatelessWidget {
  const CounterBackgroundView({
    super.key,
    required this.background,
    this.imagePath,
    this.scrim = 0.55,
    this.child,
  });

  final CounterBackground background;

  /// Overrides [CounterBackground.asset] when the event carries its own image.
  final String? imagePath;

  /// How strongly the artwork is darkened, `0..1`.
  final double scrim;

  final Widget? child;

  String? get _asset => imagePath ?? background.asset;

  @override
  Widget build(BuildContext context) {
    final asset = _asset;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: background.colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        if (asset != null)
          Image.asset(
            asset,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        if (background.glow != null)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.7, -0.9),
                radius: 1.3,
                colors: [background.glow!, Colors.transparent],
              ),
            ),
          ),
        const _SheenOverlay(),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(scrim * 0.35),
                Colors.black.withOpacity(scrim * 0.15),
                Colors.black.withOpacity(scrim),
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
        ),
        if (child != null) child!,
      ],
    );
  }
}

/// A soft diagonal highlight that gives flat gradients a sense of light.
class _SheenOverlay extends StatelessWidget {
  const _SheenOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _SheenPainter());
  }
}

class _SheenPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.10),
          Colors.white.withOpacity(0.0),
          Colors.white.withOpacity(0.04),
        ],
        stops: const [0, 0.55, 1],
      ).createShader(Offset.zero & size);

    final path = Path()
      ..moveTo(0, size.height * 0.12)
      ..quadraticBezierTo(
        size.width * 0.45,
        size.height * 0.42,
        size.width,
        size.height * 0.05,
      )
      ..lineTo(size.width, 0)
      ..lineTo(0, 0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
