import 'package:flutter/material.dart';

import 'my_images.dart';

/// A background for a counter card.
///
/// Presets are painted from gradients rather than shipped as image files, so
/// they stay sharp at any card size and cost nothing to bundle. A preset may
/// also point at a bundled [asset], which is then drawn under the gradient
/// scrim — that is the "custom image" path, and any asset added to
/// `assets/images/` can be used the same way via [CountEvent.imagePath].
class CounterBackground {
  const CounterBackground({
    required this.id,
    required this.name,
    required this.colors,
    this.glow,
    this.asset,
  });

  final String id;
  final String name;

  /// Top-left → bottom-right gradient stops.
  final List<Color> colors;

  /// Optional accent bloom painted over the gradient.
  final Color? glow;

  /// Optional bundled image drawn beneath the gradient scrim.
  final String? asset;

  bool get isPhoto => asset != null;

  /// Average of the gradient, used to pick readable foreground colours.
  Color get keyColor => Color.lerp(colors.first, colors.last, 0.5)!;
}

const kBackgroundEmber = CounterBackground(
  id: 'ember',
  name: 'Ember',
  colors: [Color(0xFF2B1710), Color(0xFF7A2F1B), Color(0xFFC0715A)],
  glow: Color(0x66FF8A5B),
);

const kBackgroundMidnight = CounterBackground(
  id: 'midnight',
  name: 'Midnight',
  colors: [Color(0xFF05070F), Color(0xFF12203D), Color(0xFF2E4E7E)],
  glow: Color(0x554F8BFF),
);

const kBackgroundAurora = CounterBackground(
  id: 'aurora',
  name: 'Aurora',
  colors: [Color(0xFF04211C), Color(0xFF0C5647), Color(0xFF43C6AC)],
  glow: Color(0x6640F0C0),
);

const kBackgroundGold = CounterBackground(
  id: 'gold',
  name: 'Gold',
  colors: [Color(0xFF1A1305), Color(0xFF6B4A0C), Color(0xFFD9A441)],
  glow: Color(0x66FFC85C),
);

const kBackgroundBloom = CounterBackground(
  id: 'bloom',
  name: 'Bloom',
  colors: [Color(0xFF1B0A20), Color(0xFF5B1B57), Color(0xFFD16BA5)],
  glow: Color(0x66FF7ACF),
);

const kBackgroundFrost = CounterBackground(
  id: 'frost',
  name: 'Frost',
  colors: [Color(0xFF0A1418), Color(0xFF1F4B57), Color(0xFF8FD3E8)],
  glow: Color(0x5573E2FF),
);

const kBackgroundNoir = CounterBackground(
  id: 'noir',
  name: 'Noir',
  colors: [Color(0xFF000000), Color(0xFF161616), Color(0xFF3A3A3A)],
  glow: Color(0x33FFFFFF),
);

const kBackgroundConcept = CounterBackground(
  id: 'concept',
  name: 'Concept i4',
  colors: [Color(0xFF120C0A), Color(0xFF2B1710), Color(0xFF52281C)],
  glow: Color(0x55FF9A6B),
  asset: kIi4Side,
);

const kBackgroundRoad = CounterBackground(
  id: 'road',
  name: 'Inspiration',
  colors: [Color(0xCC0B0B0B), Color(0x66151515), Color(0x33202020)],
  asset: kIInspiration,
);

/// Every preset offered in the background picker, gradients first.
const List<CounterBackground> kCounterBackgrounds = [
  kBackgroundEmber,
  kBackgroundMidnight,
  kBackgroundAurora,
  kBackgroundGold,
  kBackgroundBloom,
  kBackgroundFrost,
  kBackgroundNoir,
  kBackgroundConcept,
  kBackgroundRoad,
];

CounterBackground backgroundById(String id) => kCounterBackgrounds.firstWhere(
      (background) => background.id == id,
      orElse: () => kBackgroundEmber,
    );
