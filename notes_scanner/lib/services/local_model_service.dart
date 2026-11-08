import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';

enum ModelState {
  checking,
  unsupported,
  notInstalled,
  downloading,
  ready,
  error,
}

/// Owns the on-device Gemma 4 E2B model: device check, one-time download,
/// deletion, and reading a notebook page.
///
/// A single instance lives for the whole app so a download keeps going
/// (and its progress stays visible) while the user moves between screens.
class LocalModelService extends ChangeNotifier {
  LocalModelService();

  /// For widget tests: a service that never touches the platform.
  @visibleForTesting
  LocalModelService.fake(ModelState state, {this.deviceRamMb = 8192})
    : _fake = true,
      _state = state;

  static final instance = LocalModelService();

  /// Gemma 4 E2B, LiteRT-LM build that runs on GPU with CPU fallback.
  /// Apache-2.0, not gated: no Hugging Face login needed.
  static final variant = LiteRtLmModels.gemma4E2bIt.generic;
  static const displayName = 'Gemma 4 E2B';
  static int get sizeBytes => variant.file.sizeBytes;

  /// Below this the model will usually be killed for memory.
  static const minRamMb = 3500;

  /// At or above this it runs comfortably.
  static const goodRamMb = 5500;

  bool _fake = false;
  ModelState _state = ModelState.checking;
  int _progress = 0;
  String? _error;
  int? deviceRamMb;
  String? unsupportedReason;
  CancelToken? _cancel;

  ModelState get state => _state;
  int get progress => _progress;
  String? get error => _error;
  bool get isReady => _state == ModelState.ready;
  bool get lowRam => (deviceRamMb ?? 0) < goodRamMb;

  /// Registers the engine and works out what this phone can do.
  Future<void> init() async {
    if (_fake) return;
    try {
      await FlutterEdgeAi.initialize(
        inferenceEngines: const [LiteRtLmEngine()],
      );
      await _checkDevice();
      if (_state != ModelState.unsupported) {
        final installed = await FlutterEdgeAi.isModelInstalled(
          variant.file.installFilename,
        );
        _state = installed ? ModelState.ready : ModelState.notInstalled;
      }
    } catch (e) {
      // The app still works with the quick scan.
      debugPrint('On-device model unavailable: $e');
      unsupportedReason = 'The on-device model could not start on this phone.';
      _state = ModelState.unsupported;
    }
    notifyListeners();
  }

  Future<void> _checkDevice() async {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      deviceRamMb = a.physicalRamSize;
      if (!a.supported64BitAbis.contains('arm64-v8a')) {
        unsupportedReason = 'The on-device model needs a 64-bit ARM phone.';
      }
    } else if (Platform.isIOS) {
      final i = await info.iosInfo;
      deviceRamMb = i.physicalRamSize;
    } else {
      unsupportedReason = 'The on-device model runs on Android and iOS only.';
    }
    if (unsupportedReason == null && (deviceRamMb ?? 0) < minRamMb) {
      unsupportedReason =
          'This phone has ${(deviceRamMb! / 1024).toStringAsFixed(1)} GB of RAM; '
          'the on-device model needs about 4 GB or more.';
    }
    if (unsupportedReason != null) _state = ModelState.unsupported;
  }

  Future<void> download() async {
    if (_state == ModelState.downloading || _state == ModelState.ready) return;
    _state = ModelState.downloading;
    _progress = 0;
    _error = null;
    _cancel = CancelToken();
    notifyListeners();
    try {
      await FlutterEdgeAi.installModelFromCatalog(variant)
          .withProgress((p) {
            _progress = p;
            notifyListeners();
          })
          .withCancelToken(_cancel!)
          .install();
      _state = ModelState.ready;
    } catch (e) {
      if (CancelToken.isCancel(e)) {
        _state = ModelState.notInstalled;
      } else {
        _state = ModelState.error;
        _error = _friendlyDownloadError(e);
      }
    } finally {
      _cancel = null;
      notifyListeners();
    }
  }

  void cancelDownload() => _cancel?.cancel('Cancelled by user');

  Future<void> delete() async {
    await FlutterEdgeAi.uninstallModel(variant.file.installFilename);
    _state = ModelState.notInstalled;
    _progress = 0;
    notifyListeners();
  }

  static const _systemInstruction = '''
You turn a photo of a handwritten notebook page into clean notes in Markdown.
- Copy the writer's words faithfully. Fix only obvious spelling slips. Never add content that is not on the page.
- Rebuild the structure: headings (##), bullet lists, numbered lists, to-dos as "- [ ]" and ticked ones as "- [x]", and tables.
- Skip crossed-out text. Write [illegible] for a word you cannot read.
- Describe a drawing in one short italic line, like *[Diagram: ...]*.
- Reply with the Markdown only.''';

  /// Opens the model for a scan. Call [closeModel] when the scan is done:
  /// it holds a lot of memory while open.
  Future<InferenceModel> openModel() => FlutterEdgeAi.getActiveModel(
    maxTokens: 4096,
    preferredBackend: PreferredBackend.gpu,
    supportImage: true,
    maxNumImages: 1,
  );

  /// Reads one page. [ocrHint] is ML Kit's text for the same page, given to
  /// the model as a hint for hard-to-read words.
  Future<String> readPage(
    InferenceModel model, {
    required Uint8List image,
    required int pageNumber,
    required int pageCount,
    required String ocrHint,
    ValueChanged<String>? onText,
  }) async {
    final chat = await model.openChat(
      systemInstruction: _systemInstruction,
      supportImage: true,
      maxOutputTokens: 1500,
    );
    try {
      final first = pageNumber == 1;
      final prompt = StringBuffer()
        ..writeln(pageCount > 1 ? 'Page $pageNumber of $pageCount.' : '')
        ..writeln(
          first
              ? 'Start with a short title for the note as "# Title".'
              : 'This page continues the same note. Do not add a title.',
        );
      if (ocrHint.trim().isNotEmpty) {
        prompt
          ..writeln()
          ..writeln(
            'A basic text scanner read the page as below. It makes '
            'mistakes with handwriting; use it only as a hint.',
          )
          ..writeln('"""')
          ..writeln(ocrHint.trim())
          ..writeln('"""');
      }
      await chat.addQueryChunk(
        Message.withImage(
          text: prompt.toString().trim(),
          imageBytes: image,
          isUser: true,
        ),
      );
      final reply = StringBuffer();
      await for (final r in chat.generateChatResponseAsync()) {
        if (r is TextResponse) {
          reply.write(r.token);
          onText?.call(reply.toString());
        }
      }
      return cleanReply(reply.toString());
    } finally {
      await chat.close();
    }
  }

  Future<void> closeModel(InferenceModel model) => model.close();

  /// Removes a ```markdown fence the model sometimes wraps its reply in.
  static String cleanReply(String text) {
    var t = text.trim();
    final fence = RegExp(r'^```[a-zA-Z]*\s*\n([\s\S]*?)\n?```$');
    final m = fence.firstMatch(t);
    if (m != null) t = m.group(1)!.trim();
    return t;
  }

  static String _friendlyDownloadError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('space') || s.contains('storage')) {
      return 'Not enough free storage. The model needs about 2.6 GB.';
    }
    if (e is SocketException ||
        s.contains('network') ||
        s.contains('connection')) {
      return 'The download was interrupted. Check your connection and try again.';
    }
    if (e is PlatformException) return 'Download failed: ${e.message}';
    return 'Download failed. Please try again.';
  }
}
