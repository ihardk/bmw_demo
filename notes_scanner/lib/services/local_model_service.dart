import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/model_option.dart';
import 'page_prep.dart';

enum ModelState {
  checking,
  unsupported,
  notInstalled,
  downloading,
  ready,
  error,
}

class _Status {
  ModelState state = ModelState.checking;
  int progress = 0;
  String? error;
  CancelToken? cancel;
}

/// Owns the on-device models: device check, downloads, which one scans use,
/// and asking a model to read a page.
///
/// A single instance lives for the whole app so downloads keep going (and
/// their progress stays visible) while the user moves between screens.
class LocalModelService extends ChangeNotifier {
  LocalModelService();

  /// For widget tests: never touches the platform. [state] applies to the
  /// default model; [installed] lists other models to treat as downloaded.
  @visibleForTesting
  LocalModelService.fake(
    ModelState state, {
    this.deviceRamMb = 8192,
    Set<String> installed = const {},
  }) : _fake = true {
    for (final m in NoteModels.all) {
      _statusOf(m).state = m.id == NoteModels.defaultId
          ? state
          : installed.contains(m.id)
          ? ModelState.ready
          : ModelState.notInstalled;
    }
    if (state == ModelState.unsupported) _deviceUnsupported = true;
  }

  static final instance = LocalModelService();

  static const _selectedKey = 'selected_model';

  /// Below this the phone can't run any of the models.
  static const minRamMb = 3500;

  /// At or above this the default model runs comfortably.
  static const goodRamMb = 5500;

  bool _fake = false;
  bool _deviceUnsupported = false;
  final _status = <String, _Status>{};
  final _specs = <String, InferenceModelSpec>{};
  String _selectedId = NoteModels.defaultId;
  int? deviceRamMb;
  String? unsupportedReason;

  _Status _statusOf(ModelOption m) => _status.putIfAbsent(m.id, _Status.new);

  /// The model scans use.
  ModelOption get selected => NoteModels.byId(_selectedId);

  ModelState stateOf(ModelOption m) =>
      _deviceUnsupported ? ModelState.unsupported : _statusOf(m).state;
  int progressOf(ModelOption m) => _statusOf(m).progress;
  String? errorOf(ModelOption m) => _statusOf(m).error;
  bool isInstalled(ModelOption m) => stateOf(m) == ModelState.ready;

  List<ModelOption> get installed => NoteModels.all.where(isInstalled).toList();

  /// Whether the phone has the RAM a model asks for.
  bool fits(ModelOption m) => (deviceRamMb ?? 0) >= m.minRamMb;

  // The selected model, for the parts of the app that only use one.
  ModelState get state => stateOf(selected);
  int get progress => progressOf(selected);
  String? get error => errorOf(selected);
  bool get isReady => state == ModelState.ready;
  bool get lowRam => (deviceRamMb ?? 0) < goodRamMb;

  /// Registers the engine, checks the phone and what is downloaded.
  Future<void> init() async {
    if (_fake) return;
    try {
      _selectedId =
          (await SharedPreferences.getInstance()).getString(_selectedKey) ??
          NoteModels.defaultId;
      await FlutterEdgeAi.initialize(
        inferenceEngines: const [LiteRtLmEngine()],
      );
      await _checkDevice();
      for (final m in NoteModels.all) {
        final ok = await FlutterEdgeAi.isModelInstalled(m.installFilename);
        _statusOf(m).state = ok ? ModelState.ready : ModelState.notInstalled;
      }
    } catch (e) {
      // The app still works with the quick scan.
      debugPrint('On-device models unavailable: $e');
      unsupportedReason ??=
          'The on-device models could not start on this phone.';
      _deviceUnsupported = true;
    }
    notifyListeners();
  }

  Future<void> _checkDevice() async {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      deviceRamMb = a.physicalRamSize;
      if (!a.supported64BitAbis.contains('arm64-v8a')) {
        unsupportedReason = 'The on-device models need a 64-bit ARM phone.';
      }
    } else if (Platform.isIOS) {
      final i = await info.iosInfo;
      deviceRamMb = i.physicalRamSize;
    } else {
      unsupportedReason = 'The on-device models run on Android and iOS only.';
    }
    if (unsupportedReason == null && (deviceRamMb ?? 0) < minRamMb) {
      unsupportedReason =
          'This phone has ${(deviceRamMb! / 1024).toStringAsFixed(1)} GB of RAM; '
          'the on-device models need about 4 GB or more.';
    }
    if (unsupportedReason != null) _deviceUnsupported = true;
  }

  Future<void> select(ModelOption m) async {
    _selectedId = m.id;
    notifyListeners();
    if (_fake) return;
    await (await SharedPreferences.getInstance()).setString(_selectedKey, m.id);
  }

  InferenceInstallationBuilder _builder(ModelOption m) {
    final variant = m.catalogVariant;
    if (variant != null) return FlutterEdgeAi.installModelFromCatalog(variant);
    return FlutterEdgeAi.installModel(
      modelType: m.modelType,
      fileType: ModelFileType.litertlm,
    ).fromNetwork(
      m.url!,
      filename: m.installFilename,
      expectedSize: m.sizeBytes,
    );
  }

  Future<void> download(ModelOption m) async {
    final s = _statusOf(m);
    if (s.state == ModelState.downloading || s.state == ModelState.ready) {
      return;
    }
    s
      ..state = ModelState.downloading
      ..progress = 0
      ..error = null
      ..cancel = CancelToken();
    notifyListeners();
    try {
      final installation = await _builder(m)
          .withProgress((p) {
            s.progress = p;
            notifyListeners();
          })
          .withCancelToken(s.cancel!)
          .install(activate: false);
      _specs[m.id] = installation.spec;
      s.state = ModelState.ready;
    } catch (e) {
      if (CancelToken.isCancel(e)) {
        s.state = ModelState.notInstalled;
      } else {
        debugPrint('Download of ${m.name} failed: $e');
        s
          ..state = ModelState.error
          ..error = _friendlyDownloadError(e, m);
      }
    } finally {
      s.cancel = null;
      notifyListeners();
    }
  }

  void cancelDownload(ModelOption m) =>
      _statusOf(m).cancel?.cancel('Cancelled by user');

  Future<void> delete(ModelOption m) async {
    await FlutterEdgeAi.uninstallModel(m.installFilename);
    _specs.remove(m.id);
    _statusOf(m)
      ..state = ModelState.notInstalled
      ..progress = 0;
    notifyListeners();
  }

  static const _systemInstruction = '''
You turn a photo of a handwritten notebook page into clean notes in Markdown.
- Copy the writer's words faithfully. Fix only obvious spelling slips. Never add content that is not on the page.
- Rebuild the structure: headings (##), bullet lists, numbered lists, to-dos as "- [ ]" and ticked ones as "- [x]", and tables.
- Skip crossed-out text. Write [illegible] for a word you cannot read.
- Describe a drawing in one short italic line, like *[Diagram: ...]*.
- Reply with the Markdown only.''';

  /// Opens [m] (the selected model by default). Call [closeModel] when done:
  /// a model holds a lot of memory while open.
  Future<InferenceModel> openModel([ModelOption? m]) async {
    final option = m ?? selected;
    if (!isInstalled(option)) {
      throw StateError('${option.name} is not downloaded.');
    }
    // Installing an already-downloaded file again only returns its spec.
    final spec = _specs[option.id] ??= (await _builder(
      option,
    ).install(activate: false)).spec;
    return FlutterEdgeAi.openModel(
      spec,
      maxTokens: option.maxTokens,
      preferredBackend: option.backend,
      preferredVisionBackend: option.visionBackend,
      supportImage: true,
      maxNumImages: 1,
    );
  }

  Future<void> closeModel(InferenceModel model) => model.close();

  /// Reads one page with [option]. [ocrHint] is ML Kit's text for the same
  /// page; only general models get it.
  Future<String> readPage(
    InferenceModel model, {
    ModelOption? option,
    required Uint8List image,
    required int pageNumber,
    required int pageCount,
    required String ocrHint,
    ValueChanged<String>? onText,
  }) async {
    final o = option ?? selected;
    final picture = await PagePrep.prepare(image, o.shape);
    final chat = await model.openChat(
      systemInstruction: o.promptStyle == PromptStyle.notes
          ? _systemInstruction
          : null,
      supportImage: true,
      maxOutputTokens: o.maxOutputTokens,
      topK: o.greedy ? 1 : null,
    );
    try {
      final Message message;
      switch (o.promptStyle) {
        case PromptStyle.notes:
          message = Message.withImage(
            text: _notesPrompt(pageNumber, pageCount, ocrHint),
            imageBytes: picture,
            isUser: true,
          );
        case PromptStyle.task:
          message = Message.withImage(
            text: o.taskPrompt!,
            imageBytes: picture,
            isUser: true,
          );
        case PromptStyle.imageOnly:
          message = Message.imageOnly(imageBytes: picture, isUser: true);
      }
      await chat.addQueryChunk(message);
      final reply = StringBuffer();
      await for (final r in chat.generateChatResponseAsync()) {
        if (r is TextResponse) {
          reply.write(r.token);
          onText?.call(reply.toString());
        }
      }
      final text = cleanReply(reply.toString());
      return o.cleanup?.call(text) ?? text;
    } finally {
      await chat.close();
    }
  }

  static String _notesPrompt(int pageNumber, int pageCount, String ocrHint) {
    final prompt = StringBuffer()
      ..writeln(pageCount > 1 ? 'Page $pageNumber of $pageCount.' : '')
      ..writeln(
        pageNumber == 1
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
    return prompt.toString().trim();
  }

  /// Where an open model runs, as the engine reports it (after any fallback),
  /// e.g. "GPU · vision CPU".
  static String backendLabel(InferenceModel model) {
    String name(PreferredBackend? b) => b == null ? '?' : b.name.toUpperCase();
    final text = name(model.activeBackend);
    final vision = model.activeVisionBackend;
    return vision == null ? text : '$text · vision ${name(vision)}';
  }

  /// Removes a ```markdown fence and any empty thinking scaffold a model
  /// sometimes wraps its reply in.
  static String cleanReply(String text) {
    var t = text.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
    final fence = RegExp(r'^```[a-zA-Z]*\s*\n([\s\S]*?)\n?```$');
    final m = fence.firstMatch(t);
    if (m != null) t = m.group(1)!.trim();
    return t;
  }

  static String _friendlyDownloadError(Object e, ModelOption m) {
    final s = e.toString().toLowerCase();
    final gb = (m.sizeBytes / (1 << 30)).toStringAsFixed(1);
    if (s.contains('space') || s.contains('storage')) {
      return 'Not enough free storage. ${m.name} needs about $gb GB.';
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
