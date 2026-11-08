import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';

import '../models/model_option.dart';
import 'local_model_service.dart';

/// A loaded model, ready to chat.
abstract class ChatSession {
  ModelOption get option;

  /// Where the model runs, e.g. "GPU".
  String get backend;
  int get loadMs;

  /// Sends [text]; the reply streams back piece by piece (~a token each).
  Stream<String> send(String text);

  Future<void> stop();

  /// Forgets the conversation so far.
  Future<void> reset();

  Future<void> close();
}

/// Opens chat sessions; [EdgeChatEngine] in the app, a fake in tests.
abstract class ChatEngine {
  Future<ChatSession> open(ModelOption option);
}

class EdgeChatEngine implements ChatEngine {
  EdgeChatEngine(this.models);
  final LocalModelService models;

  static const _system =
      'You are a helpful assistant running entirely on the user\'s phone, '
      'with no internet access. Answer clearly and concisely. Use Markdown '
      '(lists, bold, tables) when it makes an answer easier to read.';

  @override
  Future<ChatSession> open(ModelOption option) async {
    final clock = Stopwatch()..start();
    final model = await models.openModel(option, false);
    try {
      final chat = await model.openChat(
        systemInstruction: _system,
        maxOutputTokens: 1024,
      );
      return _EdgeSession(
        option,
        model,
        chat,
        LocalModelService.backendLabel(model),
        clock.elapsedMilliseconds,
      );
    } catch (_) {
      await model.close();
      rethrow;
    }
  }
}

class _EdgeSession implements ChatSession {
  _EdgeSession(this.option, this._model, this._chat, this.backend, this.loadMs);

  @override
  final ModelOption option;
  final InferenceModel _model;
  final InferenceChat _chat;
  @override
  final String backend;
  @override
  final int loadMs;

  @override
  Stream<String> send(String text) async* {
    if (option.chat == ChatSupport.singleTurn) await _chat.clearHistory();
    await _chat.addQueryChunk(Message.text(text: text, isUser: true));
    await for (final r in _chat.generateChatResponseAsync()) {
      if (r is TextResponse) yield r.token;
    }
  }

  @override
  Future<void> stop() => _chat.stopGeneration();

  @override
  Future<void> reset() => _chat.clearHistory();

  @override
  Future<void> close() async {
    try {
      await _chat.close();
    } catch (e) {
      debugPrint('Closing chat: $e');
    }
    await _model.close();
  }
}
