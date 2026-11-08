import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/model_option.dart';

/// Gets a page photo ready for a model.
///
/// LiteRT-LM squeezes every picture into the model's fixed size and ignores
/// the EXIF orientation, so a sideways phone photo or a tall page would
/// reach the model rotated or stretched. This turns the photo upright,
/// then, for models with a fixed [ImageShape], scales it to fit and pads
/// it to exactly that shape (centred, aspect kept). Other models get the
/// upright photo with its long side capped at [maxSide].
///
/// Runs on a separate isolate: decoding a large photo takes a moment.
abstract final class PagePrep {
  static const maxSide = 1600;

  static Future<Uint8List> prepare(Uint8List bytes, ImageShape? shape) {
    final w = shape?.width, h = shape?.height, gray = shape?.padGray ?? 255;
    return Isolate.run(() => prepareSync(bytes, w, h, gray));
  }

  /// The same work on the calling isolate; for tests.
  static Uint8List prepareSync(
    Uint8List bytes,
    int? width,
    int? height,
    int gray,
  ) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes; // let the model's runtime try
    final upright = img.bakeOrientation(decoded);

    if (width == null || height == null) {
      final long = upright.width > upright.height
          ? upright.width
          : upright.height;
      final page = long <= maxSide
          ? upright
          : img.copyResize(
              upright,
              width: upright.width >= upright.height ? maxSide : null,
              height: upright.height > upright.width ? maxSide : null,
              interpolation: img.Interpolation.average,
            );
      return img.encodeJpg(page, quality: 90);
    }

    final scale = [
      width / upright.width,
      height / upright.height,
    ].reduce((a, b) => a < b ? a : b);
    final fitW = (upright.width * scale).round().clamp(1, width);
    final fitH = (upright.height * scale).round().clamp(1, height);
    final fitted = img.copyResize(
      upright,
      width: fitW,
      height: fitH,
      interpolation: img.Interpolation.average,
    );
    final canvas = img.Image(width: width, height: height)
      ..clear(img.ColorRgb8(gray, gray, gray));
    img.compositeImage(
      canvas,
      fitted,
      dstX: (width - fitW) ~/ 2,
      dstY: (height - fitH) ~/ 2,
    );
    return img.encodePng(canvas);
  }
}
