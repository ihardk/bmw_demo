import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/count_event.dart';

/// Thin bridge to the Android host for the two things Dart cannot do alone:
/// keeping events across launches, and feeding the home-screen widget.
///
/// Every call degrades quietly — on platforms without the host implementation
/// (iOS, web, desktop) the channel throws [MissingPluginException] and the app
/// simply runs with in-memory events.
class DayCounterBridge {
  DayCounterBridge._();

  static const MethodChannel _channel =
      MethodChannel('bmw_demo/day_counter');

  static bool _available = true;

  /// Whether the host answered the last call.
  static bool get isAvailable => _available;

  static Future<T?> _invoke<T>(String method, [dynamic arguments]) async {
    if (!_available) return null;
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      _available = false;
      return null;
    } on PlatformException catch (error) {
      debugPrint('DayCounterBridge.$method failed: ${error.message}');
      return null;
    }
  }

  /// Persists the whole list. Cheap enough to call on every mutation.
  static Future<void> saveEvents(List<CountEvent> events) =>
      _invoke<void>('saveEvents', CountEvent.encodeList(events));

  static Future<List<CountEvent>?> loadEvents() async {
    final raw = await _invoke<String>('loadEvents');
    if (raw == null || raw.isEmpty) return null;
    try {
      return CountEvent.decodeList(raw);
    } catch (error) {
      debugPrint('DayCounterBridge.loadEvents could not decode: $error');
      return null;
    }
  }

  /// Hands an event to the home-screen widget, along with the artwork to sit
  /// behind it. The host keeps counting days on its own from there, so the
  /// widget stays correct without the app ever being opened.
  static Future<bool> pinEvent(
    CountEvent event, {
    Uint8List? artwork,
  }) async {
    final result = await _invoke<bool>('pinEvent', {
      'event': CountEvent.encodeList([event]),
      'artwork': artwork,
    });
    return result ?? false;
  }

  /// Id of the event currently shown on the home screen, if any.
  static Future<String?> pinnedEventId() => _invoke<String>('pinnedEventId');

  /// Id of the counter whose home-screen widget launched the app, consumed on
  /// read so a later resume does not navigate again.
  static Future<String?> takeLaunchEventId() => _invoke<String>('takeLaunchEventId');

  /// Asks the launcher to place a widget for [event] (Android 8+).
  ///
  /// Returns false when the launcher has no pin support, in which case the
  /// widget still has to be dragged in from the widget tray by hand.
  static Future<bool> requestPinToHomeScreen(CountEvent event) async {
    final result = await _invoke<bool>('requestPin', {'id': event.id});
    return result ?? false;
  }
}
