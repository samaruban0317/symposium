/// The installable-model catalog: what the Ollama library has on offer.
/// Plain data + a bundled fallback so the install browser works offline.
library;

class CatalogEntry {
  final String name; // library name, e.g. "qwen2.5"
  final String description;
  final List<String> sizes; // tag chips, e.g. ["0.5b", "1.5b", "7b"]
  final String? pulls; // "117.3M" — social proof from the live page

  /// What the model can do beyond chat: "vision", "tools", "thinking",
  /// "embedding" — the library page's purple capability chips.
  final List<String> capabilities;

  const CatalogEntry({
    required this.name,
    required this.description,
    this.sizes = const [],
    this.pulls,
    this.capabilities = const [],
  });

  /// What `ollama pull` should be given when a size chip is chosen.
  String tagFor(String? size) => size == null ? name : '$name:$size';
}

/// Rough hardware needs for one size tag, derived from parameter count.
/// Library tags ship q4-ish quantization, so ~0.65 GB of weights per billion
/// parameters, plus headroom for the KV cache and the OS. Estimates, not
/// promises — but close enough to answer "will this run on my machine?".
class ModelReqs {
  final double downloadGB;
  final double ramGB; // minimum comfortable total RAM/VRAM

  const ModelReqs({required this.downloadGB, required this.ramGB});

  /// Parses "0.5b", "135m", "3.8b", "8x7b" (MoE — all experts stay in
  /// memory). Returns null for non-numeric tags like "latest" or "instruct".
  static ModelReqs? forSize(String size) {
    final m = RegExp(r'^(?:(\d+)x)?(\d+(?:\.\d+)?)([bm])$')
        .firstMatch(size.trim().toLowerCase());
    if (m == null) return null;
    final multiplier = int.tryParse(m.group(1) ?? '') ?? 1;
    var billions = double.parse(m.group(2)!) * multiplier;
    if (m.group(3) == 'm') billions /= 1000;
    final weights = billions * 0.65;
    return ModelReqs(
      downloadGB: weights,
      ramGB: weights + (billions < 4 ? 1.5 : 2.5),
    );
  }

  String get downloadLabel => downloadGB < 1
      ? '${(downloadGB * 1024).round()} MB'
      : '${downloadGB.toStringAsFixed(1)} GB';

  String get ramLabel =>
      '${ramGB < 2 ? ramGB.toStringAsFixed(1) : ramGB.ceil().toString()} GB';
}

/// Shipped snapshot of the library's most-pulled models — used when
/// ollama.com is unreachable (offline LAN party, firewalled network).
/// The live fetch replaces this whenever it succeeds.
const kFallbackCatalog = <CatalogEntry>[
  CatalogEntry(
      name: 'llama3.2',
      description: "Meta's small instruction-tuned models — a strong default.",
      sizes: ['1b', '3b'],
      capabilities: ['tools']),
  CatalogEntry(
      name: 'llama3.1',
      description: 'Meta Llama 3.1 — the 8b runs well on most PCs.',
      sizes: ['8b', '70b'],
      capabilities: ['tools']),
  CatalogEntry(
      name: 'qwen2.5',
      description: "Alibaba's all-rounder family, tiny to huge.",
      sizes: ['0.5b', '1.5b', '3b', '7b', '14b', '32b', '72b'],
      capabilities: ['tools']),
  CatalogEntry(
      name: 'qwen2.5-coder',
      description: 'Qwen tuned for code completion and repair.',
      sizes: ['0.5b', '1.5b', '3b', '7b', '14b', '32b'],
      capabilities: ['tools']),
  CatalogEntry(
      name: 'qwen3',
      description: 'Latest Qwen generation with thinking mode.',
      sizes: ['0.6b', '1.7b', '4b', '8b', '14b', '32b'],
      capabilities: ['tools', 'thinking']),
  CatalogEntry(
      name: 'gemma2',
      description: "Google's Gemma 2 — strong quality for the size.",
      sizes: ['2b', '9b', '27b']),
  CatalogEntry(
      name: 'gemma3',
      description: 'Gemma 3 — sees images, runs on a single GPU.',
      sizes: ['1b', '4b', '12b', '27b'],
      capabilities: ['vision']),
  CatalogEntry(
      name: 'llama3.2-vision',
      description: 'Llama that reads images: photos, charts, screenshots.',
      sizes: ['11b', '90b'],
      capabilities: ['vision']),
  CatalogEntry(
      name: 'llava',
      description: 'Vision + language: describe and discuss images.',
      sizes: ['7b', '13b', '34b'],
      capabilities: ['vision']),
  CatalogEntry(
      name: 'qwen2.5vl',
      description: 'Qwen vision-language — strong OCR and document reading.',
      sizes: ['3b', '7b', '32b', '72b'],
      capabilities: ['vision']),
  CatalogEntry(
      name: 'minicpm-v',
      description: 'Compact vision model rivaling much larger ones.',
      sizes: ['8b'],
      capabilities: ['vision']),
  CatalogEntry(
      name: 'moondream',
      description: 'Tiny vision model built for edge devices.',
      sizes: ['1.8b'],
      capabilities: ['vision']),
  CatalogEntry(
      name: 'granite3.2-vision',
      description: "IBM's document-understanding vision model.",
      sizes: ['2b'],
      capabilities: ['vision']),
  CatalogEntry(
      name: 'deepseek-r1',
      description: 'Reasoning model that shows its chain of thought.',
      sizes: ['1.5b', '7b', '8b', '14b', '32b', '70b'],
      capabilities: ['thinking']),
  CatalogEntry(
      name: 'phi4',
      description: "Microsoft's 14b — punches far above its weight.",
      sizes: ['14b']),
  CatalogEntry(
      name: 'phi4-mini',
      description: 'Small Phi-4 with strong reasoning and multilingual skills.',
      sizes: ['3.8b'],
      capabilities: ['tools']),
  CatalogEntry(
      name: 'mistral',
      description: 'Mistral 7B — the classic fast open model.',
      sizes: ['7b'],
      capabilities: ['tools']),
  CatalogEntry(
      name: 'mistral-nemo',
      description: 'Mistral + NVIDIA 12b with a 128k context window.',
      sizes: ['12b'],
      capabilities: ['tools']),
  CatalogEntry(
      name: 'smollm2',
      description: 'HuggingFace small models — surprisingly capable.',
      sizes: ['135m', '360m', '1.7b'],
      capabilities: ['tools']),
  CatalogEntry(
      name: 'tinyllama',
      description: '1.1b trained on 3T tokens — fits anywhere.',
      sizes: ['1.1b']),
  CatalogEntry(
      name: 'codellama',
      description: 'Llama tuned for writing and explaining code.',
      sizes: ['7b', '13b', '34b', '70b']),
  CatalogEntry(
      name: 'starcoder2',
      description: 'Code generation in 600+ languages.',
      sizes: ['3b', '7b', '15b']),
  CatalogEntry(
      name: 'dolphin3',
      description: 'General-purpose instruct tune of Llama 3.1 8b.',
      sizes: ['8b']),
  CatalogEntry(
      name: 'olmo2',
      description: "AllenAI's fully open models — weights and data.",
      sizes: ['7b', '13b']),
  CatalogEntry(
      name: 'granite3.3',
      description: "IBM's Granite with 128k context.",
      sizes: ['2b', '8b'],
      capabilities: ['tools']),
  CatalogEntry(
      name: 'mixtral',
      description: 'Mixture-of-experts from Mistral — needs real RAM.',
      sizes: ['8x7b', '8x22b'],
      capabilities: ['tools']),
  CatalogEntry(
      name: 'nomic-embed-text',
      description: 'Text embeddings for search and RAG.',
      capabilities: ['embedding']),
  CatalogEntry(
      name: 'mxbai-embed-large',
      description: 'Large embedding model from Mixedbread.',
      capabilities: ['embedding']),
];
