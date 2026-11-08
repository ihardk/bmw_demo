import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';

/// How a model wants to be asked.
enum PromptStyle {
  /// A general vision model: our note-making instructions, plus ML Kit's
  /// text as a hint.
  notes,

  /// An OCR specialist that only answers its own task prompt, given in
  /// [ModelOption.taskPrompt]. Our instructions would only confuse it.
  task,

  /// The model's file writes its own instruction; send the picture alone.
  imageOnly,
}

/// How well a model holds a text conversation.
enum ChatSupport {
  /// OCR specialists: they only transcribe pages.
  none,

  /// Answers each message on its own (its card reports later turns of a
  /// conversation degrade on this runtime).
  singleTurn,

  /// A normal back-and-forth conversation.
  multiTurn,
}

/// The fixed picture size a model's runtime squeezes every image into. The
/// runtime keeps neither the aspect ratio nor the EXIF orientation, so the
/// app turns the page upright and pads it to this shape first.
class ImageShape {
  const ImageShape(this.width, this.height, {this.padGray = 255});
  final int width;
  final int height;

  /// Padding colour, 0–255 gray (white for most models).
  final int padGray;
}

/// One on-device model the app can download and run. The numbers and quirks
/// come from each model's Hugging Face card.
class ModelOption {
  const ModelOption({
    required this.id,
    required this.name,
    required this.maker,
    required this.kind,
    required this.about,
    required this.sizeBytes,
    required this.modelType,
    this.catalogVariant,
    this.repo,
    this.revision,
    this.file,
    this.promptStyle = PromptStyle.notes,
    this.taskPrompt,
    this.shape,
    this.backend = PreferredBackend.gpu,
    this.visionBackend,
    this.greedy = false,
    this.enginePerPage = false,
    this.maxTokens = 4096,
    this.maxOutputTokens = 1500,
    this.minRamMb = 4000,
    this.heavy,
    this.cleanup,
    this.chat = ChatSupport.none,
  }) : assert(catalogVariant != null || (repo != null && file != null));

  final String id;
  final String name;
  final String maker;

  /// "General vision" or "OCR specialist".
  final String kind;

  /// One or two lines for the model list.
  final String about;
  final int sizeBytes;
  final ModelType modelType;

  /// Either a build from the runtime's own catalog...
  final LiteRtLmVariant? catalogVariant;

  /// ...or a file on Hugging Face, pinned to a commit.
  final String? repo;
  final String? revision;
  final String? file;

  final PromptStyle promptStyle;
  final String? taskPrompt;
  final ImageShape? shape;
  final PreferredBackend backend;
  final PreferredBackend? visionBackend;

  /// Always pick the most likely word (what OCR models are tested with).
  final bool greedy;

  /// Hybrid models carry state from one conversation into the next on the
  /// same engine, so they get a fresh engine for every page.
  final bool enginePerPage;

  /// Context window (prompt + image + answer) and the answer's cap.
  final int maxTokens;
  final int maxOutputTokens;

  /// Below this much phone RAM the model will likely be killed.
  final int minRamMb;

  /// A warning shown before downloading, if any.
  final String? heavy;

  /// Turns the model's raw reply into Markdown, if it needs it.
  final String Function(String)? cleanup;

  /// Whether the Chat screen offers this model.
  final ChatSupport chat;
  bool get canChat => chat != ChatSupport.none;

  /// The name the file is stored under on the phone. Unique per model.
  String get installFilename =>
      catalogVariant?.file.installFilename ?? '${id}__${file!}';

  String? get url => repo == null
      ? null
      : 'https://huggingface.co/$repo/resolve/${revision ?? 'main'}/$file';

  bool get isSpecialist => kind == NoteModels.ocr;
}

abstract final class NoteModels {
  static const general = 'General vision';
  static const ocr = 'OCR specialist';

  static const defaultId = 'gemma-4-e2b';

  static ModelOption byId(String id) =>
      all.firstWhere((m) => m.id == id, orElse: () => all.first);

  static final List<ModelOption> all = [
    ModelOption(
      id: defaultId,
      name: 'Gemma 4 E2B',
      maker: 'Google',
      kind: general,
      about:
          'Reads messy handwriting and organises it into headings, lists '
          'and to-dos. The default.',
      sizeBytes: LiteRtLmModels.gemma4E2bIt.generic.file.sizeBytes,
      modelType: ModelType.gemma4,
      catalogVariant: LiteRtLmModels.gemma4E2bIt.generic,
      chat: ChatSupport.multiTurn,
    ),
    ModelOption(
      id: 'gemma-4-e4b',
      name: 'Gemma 4 E4B',
      maker: 'Google',
      kind: general,
      about:
          'The bigger Gemma 4: usually reads better, roughly half the '
          'speed. Wants a phone with 8 GB of RAM or more.',
      sizeBytes: LiteRtLmModels.gemma4E4bIt.generic.file.sizeBytes,
      modelType: ModelType.gemma4,
      catalogVariant: LiteRtLmModels.gemma4E4bIt.generic,
      minRamMb: 7000,
      chat: ChatSupport.multiTurn,
    ),
    ModelOption(
      id: 'qwen2-vl-2b',
      name: 'Qwen2-VL 2B',
      maker: 'Alibaba Qwen',
      kind: general,
      about:
          'General vision model with strong text reading. Sees the page '
          'at 672×672.',
      sizeBytes: LiteRtLmModels.qwen2Vl2b.generic.file.sizeBytes,
      modelType: ModelType.general,
      catalogVariant: LiteRtLmModels.qwen2Vl2b.generic,
      shape: const ImageShape(672, 672),
      chat: ChatSupport.multiTurn,
    ),
    const ModelOption(
      id: 'internvl3.5-2b',
      name: 'InternVL3.5 2B',
      maker: 'Shanghai AI Lab',
      kind: general,
      about:
          'General vision model, good at documents. Sees the page at '
          '448×448, so small writing may blur.',
      sizeBytes: 1613223280,
      modelType: ModelType.general,
      repo: 'litert-community/InternVL3_5-2B',
      revision: 'b62b8ba312c0918345e237b675b1b0f0c8a1bf91',
      file: 'model.litertlm',
      shape: ImageShape(448, 448),
      chat: ChatSupport.singleTurn,
    ),
    const ModelOption(
      id: 'lfm2.5-vl-1.6b',
      name: 'LFM2.5-VL 1.6B',
      maker: 'Liquid AI',
      kind: general,
      about: 'Small, fast general vision model. Sees the page at 512×512.',
      sizeBytes: 1298139472,
      modelType: ModelType.general,
      repo: 'litert-community/LFM2.5-VL-1.6B',
      revision: 'c8e1a58ab91df9e619edf3b74418cf54a69f3fa5',
      file: 'LFM2.5-VL-1.6B_int4_fixB.litertlm',
      shape: ImageShape(512, 512),
      enginePerPage: true,
      chat: ChatSupport.multiTurn,
    ),
    const ModelOption(
      id: 'xiaomi-ocr-0',
      name: 'Xiaomi-OCR-0',
      maker: 'Xiaomi',
      kind: ocr,
      about:
          '0.8B OCR model, top of the document benchmarks. Runs on the '
          'CPU, ~10–15 s a page. Its card says handwriting is a weak spot.',
      sizeBytes: 1314747056,
      modelType: ModelType.qwen35,
      repo: 'litert-community/Xiaomi-OCR-0',
      revision: 'd7b2bcbb85e6c4e0061467ae4cdff9cb474b19e3',
      file: 'Xiaomi-OCR-0_int8.litertlm',
      promptStyle: PromptStyle.task,
      taskPrompt:
          'Extract all information from the main body of the '
          'document image and represent it in markdown format, ignoring '
          'headers and footers. Tables should be expressed in OTSL format, '
          'formulas in the document should be represented using LATEX '
          'format, and the parsing should be organized according to the '
          'reading order.',
      shape: ImageShape(768, 1344),
      backend: PreferredBackend.cpu,
      visionBackend: PreferredBackend.cpu,
      greedy: true,
      enginePerPage: true,
      maxOutputTokens: 2800,
    ),
    const ModelOption(
      id: 'paddleocr-vl-1.6',
      name: 'PaddleOCR-VL 1.6',
      maker: 'Baidu PaddlePaddle',
      kind: ocr,
      about:
          '0.9B document OCR model. Needs the GPU (it writes nonsense '
          'on the CPU). Sees the page at 560×560.',
      sizeBytes: 1390305472,
      modelType: ModelType.general,
      repo: 'litert-community/PaddleOCR-VL-1.6',
      revision: '51dc08592f3919404a18b3d2820ee84e8ff23ff4',
      file: 'PaddleOCR-VL-1.6.litertlm',
      promptStyle: PromptStyle.task,
      taskPrompt: 'OCR:',
      shape: ImageShape(560, 560),
      greedy: true,
    ),
    const ModelOption(
      id: 'ovis-ocr2',
      name: 'OvisOCR2',
      maker: 'Alibaba AIDC (community conversion)',
      kind: ocr,
      about:
          '0.8B OCR model that writes Markdown. Runs on the CPU. Sees the '
          'page at 512×512.',
      sizeBytes: 1302262448,
      modelType: ModelType.qwen35,
      repo: 'mlboydaisuke/OvisOCR2-LiteRT',
      revision: 'f5353aa4792675f7c5ecc405bb293847a07ce87e',
      file: 'OvisOCR2_int8.litertlm',
      promptStyle: PromptStyle.task,
      taskPrompt:
          'Extract all readable content from the image in natural '
          'human reading order and output the result as a single Markdown '
          'document. For charts or images, represent them using an HTML '
          'image tag: <img src="images/bbox_{left}_{top}_{right}_{bottom}.jpg" />, '
          'where left, top, right, bottom are bounding box coordinates '
          'scaled to [0, 1000). Format formulas as LaTeX. Format tables as '
          'HTML: <table>...</table>. Transcribe all other text as standard '
          'Markdown. Preserve the original text without translation or '
          'paraphrasing.',
      shape: ImageShape(512, 512),
      backend: PreferredBackend.cpu,
      visionBackend: PreferredBackend.cpu,
      greedy: true,
      enginePerPage: true,
      maxOutputTokens: 2500,
    ),
    const ModelOption(
      id: 'unlimited-ocr-2',
      name: 'Unlimited-OCR-2',
      maker: 'Baidu',
      kind: ocr,
      about:
          '3.3B document parser, the newest and biggest here. Runs on '
          'the CPU, ~20–30 s a page. Sees the page at 1024×1024.',
      sizeBytes: 3812443693,
      modelType: ModelType.general,
      repo: 'litert-community/Unlimited-OCR-2',
      revision: '1989a269214e560e43d8e89b8c8da85ae0a6c4ce',
      file: 'Unlimited-OCR-2_int8.litertlm',
      promptStyle: PromptStyle.imageOnly,
      shape: ImageShape(1024, 1024, padGray: 127),
      backend: PreferredBackend.cpu,
      visionBackend: PreferredBackend.cpu,
      greedy: true,
      enginePerPage: true,
      maxOutputTokens: 2800,
      minRamMb: 7000,
      heavy:
          'Needs about 8 GB of free storage in all: the 3.8 GB file plus '
          'about 4.4 GB of runtime cache written on first use. Wants a '
          'phone with 8 GB of RAM or more.',
      cleanup: cleanUnlimitedOcr,
    ),
  ];

  /// Unlimited-OCR-2 replies `<PAGE>` then, per block,
  /// `<BLOCK>label[x1, y1, x2, y2]<FORK>content`. Keep the content, make
  /// titles headings.
  static String cleanUnlimitedOcr(String raw) {
    final out = <String>[];
    for (final block in raw.split('<BLOCK>').skip(1)) {
      final fork = block.indexOf('<FORK>');
      if (fork < 0) continue;
      final label = block
          .substring(0, fork)
          .split('[')
          .first
          .trim()
          .toLowerCase();
      final content = block
          .substring(fork + 6)
          .replaceAll(RegExp(r'</?(PAGE|BLOCK|FORK)>'), '')
          .trim();
      if (content.isEmpty) continue;
      out.add(
        label.contains('title') && !content.startsWith('#')
            ? '## $content'
            : content,
      );
    }
    if (out.isEmpty) {
      return raw.replaceAll(RegExp(r'</?(PAGE|BLOCK|FORK)>'), '').trim();
    }
    return out.join('\n\n');
  }
}
