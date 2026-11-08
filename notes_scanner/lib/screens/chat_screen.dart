import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart'
    show ContextLimitException;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/model_option.dart';
import '../services/chat_engine.dart';
import '../services/local_model_service.dart';
import '../services/memory_monitor.dart';
import '../services/scan_queue.dart';
import 'activity_screen.dart' show formatMb, formatMs;
import 'models_screen.dart';

class _Msg {
  _Msg.user(this.text) : fromUser = true;
  _Msg.reply() : fromUser = false, text = '';

  final bool fromUser;
  String text;
  bool streaming = false;
  String? error;
  int tokens = 0;
  int? firstTokenMs;
  double? tokensPerSec;
}

/// Text chat with an on-device model. Everything stays on the phone; the
/// conversation is kept only while this screen is open.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.model,
    required this.engine,
    required this.memory,
    required this.queue,
  });

  final LocalModelService model;
  final ChatEngine engine;
  final MemoryMonitor memory;
  final ScanQueue queue;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Msg>[];
  ModelOption? _option;
  ChatSession? _session;
  bool _loading = false;
  String? _loadError;
  StreamSubscription<String>? _reply;

  List<ModelOption> get _chatModels =>
      widget.model.installed.where((m) => m.canChat).toList();

  bool get _busy => _reply != null;

  @override
  void initState() {
    super.initState();
    final models = _chatModels;
    final selected = widget.model.selected;
    _option = models.contains(selected)
        ? selected
        : models.isEmpty
        ? null
        : models.first;
    if (_option != null) _load(_option!);
  }

  @override
  void dispose() {
    _reply?.cancel();
    _session?.close();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load(ModelOption option) async {
    await _reply?.cancel();
    _reply = null;
    final old = _session;
    setState(() {
      _option = option;
      _session = null;
      _loading = true;
      _loadError = null;
    });
    await old?.close();
    try {
      final s = await widget.engine.open(option);
      if (!mounted || _option != option) {
        await s.close();
        return;
      }
      setState(() => _session = s);
    } catch (e) {
      debugPrint('Chat: could not load ${option.name}: $e');
      if (mounted) {
        setState(
          () => _loadError =
              '${option.name} could not start (often low memory). '
              'Close other apps or pick a smaller model.',
        );
      }
    } finally {
      if (mounted && _option == option) setState(() => _loading = false);
    }
  }

  Future<void> _newChat() async {
    if (_busy) await _stop();
    setState(_messages.clear);
    final s = _session;
    if (s == null) return;
    // Hybrid models carry state across conversations on one engine.
    if (s.option.enginePerPage) {
      await _load(s.option);
    } else {
      await s.reset();
    }
  }

  Future<void> _stop() async {
    await _session?.stop();
  }

  void _send([String? preset]) {
    final text = (preset ?? _input.text).trim();
    final s = _session;
    if (text.isEmpty || s == null || _busy) return;
    _input.clear();
    final reply = _Msg.reply()..streaming = true;
    setState(
      () => _messages
        ..add(_Msg.user(text))
        ..add(reply),
    );
    _scrollToEnd();

    final clock = Stopwatch()..start();
    _reply = s
        .send(text)
        .listen(
          (piece) {
            reply
              ..text += piece
              ..tokens += 1;
            final now = clock.elapsedMilliseconds;
            reply.firstTokenMs ??= now;
            final decoding = now - reply.firstTokenMs!;
            if (reply.tokens > 1 && decoding > 0) {
              reply.tokensPerSec = (reply.tokens - 1) * 1000 / decoding;
            }
            setState(() {});
            _scrollToEnd();
          },
          onError: (Object e) {
            reply.error = e is ContextLimitException
                ? 'This chat is full: the model holds about '
                      '${s.option.maxTokens} tokens. Start a new chat.'
                : 'The model stopped with an error. Try again or start a new chat.';
            debugPrint('Chat error: $e');
            _finish(reply);
          },
          onDone: () => _finish(reply),
          cancelOnError: true,
        );
  }

  void _finish(_Msg reply) {
    if (!mounted) return;
    setState(() {
      reply.streaming = false;
      reply.text = LocalModelService.cleanReply(reply.text);
      if (reply.text.isEmpty && reply.error == null) {
        reply.error = 'Stopped before it answered.';
      }
      _reply = null;
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final models = _chatModels;
    return Scaffold(
      appBar: AppBar(
        title: models.isEmpty
            ? const Text('Chat')
            : DropdownButtonHideUnderline(
                child: DropdownButton<ModelOption>(
                  value: _option,
                  isExpanded: true,
                  items: [
                    for (final m in models)
                      DropdownMenuItem(value: m, child: Text(m.name)),
                  ],
                  onChanged: _busy
                      ? null
                      : (m) {
                          if (m != null && m != _option) {
                            setState(_messages.clear);
                            _load(m);
                          }
                        },
                ),
              ),
        actions: [
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _session == null || _messages.isEmpty ? null : _newChat,
          ),
        ],
      ),
      body: models.isEmpty ? _noModels(context) : _chat(context),
    );
  }

  Widget _noModels(BuildContext context) {
    final downloaded = widget.model.installed.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.forum_outlined, size: 64),
            const SizedBox(height: 16),
            Text(
              downloaded
                  ? 'Your downloaded models only read pages and can\'t chat.'
                  : 'No chat model downloaded yet.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Gemma 4 E2B is the best one for chatting.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ModelsScreen(model: widget.model),
                ),
              ),
              icon: const Icon(Icons.download),
              label: const Text('Get models'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chat(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        // Model, backend, load time and memory, live.
        ListenableBuilder(
          listenable: widget.memory,
          builder: (context, _) {
            final s = _session;
            final ram = widget.memory.latest?.appMb;
            final parts = [
              if (_loading) 'Loading ${_option?.name}…',
              if (s != null) s.backend,
              if (s != null) 'loaded in ${formatMs(s.loadMs)}',
              if (ram != null) 'App RAM ${formatMb(ram)}',
              if (_option?.chat == ChatSupport.singleTurn)
                'answers each message on its own',
            ];
            return Container(
              width: double.infinity,
              color: scheme.surfaceContainerHigh,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(parts.join(' · '), style: text.labelSmall),
            );
          },
        ),
        if (_loading) const LinearProgressIndicator(),
        ListenableBuilder(
          listenable: widget.queue,
          builder: (context, _) => widget.queue.busy
              ? Container(
                  width: double.infinity,
                  color: scheme.tertiaryContainer,
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'A scan is running too. Two models at once use a lot of '
                    'memory and both will be slower.',
                    style: text.bodySmall,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => _load(_option!),
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : _messages.isEmpty
              ? _suggestions(context)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _Bubble(msg: _messages[i]),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    enabled: _session != null,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: _session == null
                          ? 'Loading model…'
                          : 'Message ${_option?.name}',
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _busy
                    ? IconButton.filledTonal(
                        tooltip: 'Stop',
                        icon: const Icon(Icons.stop),
                        onPressed: _stop,
                      )
                    : IconButton.filled(
                        tooltip: 'Send',
                        icon: const Icon(Icons.arrow_upward),
                        onPressed: _session == null ? null : () => _send(),
                      ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _suggestions(BuildContext context) {
    const ideas = [
      'Explain photosynthesis in simple words',
      'Make me a study plan for this week',
      'Give me 5 quiz questions on World War II',
      'How do I write a good summary?',
    ];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.forum_outlined, size: 48),
        const SizedBox(height: 12),
        Text(
          'Chat with ${_option?.name ?? 'the model'}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        const Text(
          'Runs on this phone, works offline. Nothing is saved after you '
          'leave this screen.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final idea in ideas)
              ActionChip(
                label: Text(idea),
                onPressed: _session == null ? null : () => _send(idea),
              ),
          ],
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg});
  final _Msg msg;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final user = msg.fromUser;
    final stats = [
      if (msg.firstTokenMs != null) 'first word ${formatMs(msg.firstTokenMs!)}',
      if (msg.tokensPerSec != null)
        '${msg.tokensPerSec!.toStringAsFixed(1)} tok/s',
      if (msg.tokens > 0) '${msg.tokens} tokens',
    ];
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: msg.text.isEmpty
            ? null
            : () {
                Clipboard.setData(ClipboardData(text: msg.text));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Copied')));
              },
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * (user ? 0.8 : 0.92),
          ),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: user
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (user)
                SelectableText(msg.text)
              else if (msg.text.isEmpty && msg.streaming)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (msg.text.isNotEmpty)
                MarkdownBody(data: msg.text, selectable: true),
              if (msg.error != null)
                Padding(
                  padding: EdgeInsets.only(top: msg.text.isEmpty ? 0 : 6),
                  child: Text(
                    msg.error!,
                    style: text.bodySmall?.copyWith(color: scheme.error),
                  ),
                ),
              if (!user && stats.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  [...stats, if (msg.streaming) 'writing…'].join(' · '),
                  style: text.labelSmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
