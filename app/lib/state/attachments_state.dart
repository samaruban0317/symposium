/// Pending chat attachments: what's clipped to the composer, waiting to ride
/// along with the next message.
///
/// Images go to the model as base64 content parts (vision models only —
/// llava, gemma3, qwen2.5vl…). Documents are converted to text right here at
/// attach time: PDFs through a pure-Dart extractor, everything else read as
/// UTF-8. The model only ever sees text and images; it never "opens" a file.
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PendingAttachments {
  final List<String> images; // base64
  final String? docName;
  final String? docText;
  final String? error; // last attach problem, shown inline until next action

  const PendingAttachments({
    this.images = const [],
    this.docName,
    this.docText,
    this.error,
  });

  bool get isEmpty => images.isEmpty && docName == null;

  PendingAttachments copyWith({
    List<String>? images,
    String? docName,
    String? docText,
    String? error,
    bool clearDoc = false,
  }) =>
      PendingAttachments(
        images: images ?? this.images,
        docName: clearDoc ? null : (docName ?? this.docName),
        docText: clearDoc ? null : (docText ?? this.docText),
        error: error,
      );
}

class AttachmentsController extends StateNotifier<PendingAttachments> {
  static const _maxImages = 4;
  static const _maxImageBytes = 8 * 1024 * 1024;
  static const _maxDocChars = 24000; // ~6k tokens — plenty for small contexts

  AttachmentsController() : super(const PendingAttachments());

  Future<void> pickImage() async {
    if (state.images.length >= _maxImages) {
      state = state.copyWith(error: 'up to $_maxImages images per message');
      return;
    }
    final res = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = res?.files.firstOrNull;
    final bytes = file?.bytes;
    if (bytes == null) return; // cancelled
    if (bytes.length > _maxImageBytes) {
      state = state.copyWith(error: 'image too large (max 8 MB)');
      return;
    }
    state = state.copyWith(images: [...state.images, base64Encode(bytes)]);
  }

  Future<void> pickDocument() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'pdf', 'txt', 'md', 'csv', 'json', 'log', 'xml', 'yaml', 'yml',
        'html', 'css', 'js', 'ts', 'dart', 'py', 'java', 'c', 'cpp', 'sh',
      ],
      withData: true,
    );
    final file = res?.files.firstOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return; // cancelled
    try {
      String text;
      if (file.extension?.toLowerCase() == 'pdf') {
        final doc = PdfDocument(inputBytes: bytes);
        try {
          text = PdfTextExtractor(doc).extractText();
        } finally {
          doc.dispose();
        }
        if (text.trim().isEmpty) {
          state = state.copyWith(
              error: 'no text in this PDF — it may be scanned images');
          return;
        }
      } else {
        text = const Utf8Decoder(allowMalformed: true).convert(bytes);
      }
      if (text.length > _maxDocChars) {
        text = '${text.substring(0, _maxDocChars)}\n…[truncated]';
      }
      state = state.copyWith(docName: file.name, docText: text);
    } catch (e) {
      state = state.copyWith(error: 'could not read ${file.name}: $e');
    }
  }

  void removeImage(int index) => state = state.copyWith(
      images: [...state.images]..removeAt(index));

  void removeDoc() => state = state.copyWith(clearDoc: true);

  void clear() => state = const PendingAttachments();
}

final attachmentsProvider =
    StateNotifierProvider<AttachmentsController, PendingAttachments>(
        (_) => AttachmentsController());
