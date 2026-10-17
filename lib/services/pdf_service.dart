import 'dart:io';
import 'dart:typed_data' show Uint8List;
import 'dart:ui' show Offset, Rect;
import 'package:flutter/services.dart' show rootBundle;
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfService {
  static Uint8List? _regBytes;
  static Uint8List? _boldBytes;

  static Future<void> _ensureFonts() async {
    if (_regBytes != null && _boldBytes != null) return;
    final reg = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    _regBytes = reg.buffer.asUint8List();
    _boldBytes = bold.buffer.asUint8List();
  }

  static Future<File?> mergePdfs({
    required List<String> inputPaths,
    required String outputPath,
    String? playlistName,
  }) async {
    if (inputPaths.isEmpty) return null;

    try {
      await _ensureFonts();
    } catch (e) {
      // ignore: avoid_print
      print('Błąd ładowania czcionek: $e');
      return null;
    }
    if (_regBytes == null || _boldBytes == null) return null;

    final output = PdfDocument();
    PdfSection? section;

    // === 1. Zbierz tytuły + tonacje ===
    final titles = <String>[];
    final keys = <String>[];
    for (final path in inputPaths) {
      final name = path.split('/').last;
      final titleNoExt = name.replaceAll(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );
      titles.add(titleNoExt);

      var key = '';
      try {
        final f = File(path);
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          final doc = PdfDocument(inputBytes: bytes);
          if (doc.pages.count > 0) {
            final text = PdfTextExtractor(doc).extractText(
              startPageIndex: 0,
              endPageIndex: 0,
            );
            // Pierwszy niepusty wiersz — 6 znaków od prawej (tonacja).
            final firstLine = text
                .split('\n')
                .map((s) => s.trim())
                .firstWhere((s) => s.isNotEmpty, orElse: () => '');
            if (firstLine.length >= 6) {
              key = firstLine.substring(firstLine.length - 6).trim();
            } else {
              key = firstLine;
            }
          }
          doc.dispose();
        }
      } catch (_) {}
      keys.add(key);
    }

    // === 2. Spis utworów ===
    final tocSection = output.sections!.add();
    tocSection.pageSettings.size = PdfPageSize.a4;
    tocSection.pageSettings.margins.all = 30;
    final tocPage = tocSection.pages.add();
    final tocGraphics = tocPage.graphics;

    var y = 0.0;
    if (playlistName?.trim().isNotEmpty == true) {
      final titleFont = PdfTrueTypeFont(_boldBytes!, 30);
      // Wyśrodkowanie — PdfStringFormat z alignment center.
      final format = PdfStringFormat(
        alignment: PdfTextAlignment.center,
      );
      tocGraphics.drawString(
        playlistName!.trim(),
        titleFont,
        bounds: Rect.fromLTWH(0, y, 535, 40),
        format: format,
      );
      y += 50;
    }

    const availableHeight = 737.0;
    final count = inputPaths.length;
    var lineHeight = count > 0 ? availableHeight / count : 20.0;
    if (lineHeight > 40) lineHeight = 40;
    if (lineHeight < 14) lineHeight = 14;
    var fontSize = lineHeight * 0.75;
    if (fontSize > 22) fontSize = 22;
    if (fontSize < 10) fontSize = 10;

    final fontEntry = PdfTrueTypeFont(_regBytes!, fontSize);
    final fontNumber = PdfTrueTypeFont(_boldBytes!, fontSize);
    final fontKey = PdfTrueTypeFont(_regBytes!, fontSize * 0.85);

    for (var i = 0; i < count; i++) {
      if (y > 800) break;
      tocGraphics.drawString(
        '${i + 1}.',
        fontNumber,
        bounds: Rect.fromLTWH(0, y, 40, lineHeight),
      );
      tocGraphics.drawString(
        titles[i],
        fontEntry,
        bounds: Rect.fromLTWH(40, y, 400, lineHeight),
      );
      if (keys[i].isNotEmpty) {
        tocGraphics.drawString(
          keys[i],
          fontKey,
          bounds: Rect.fromLTWH(440, y, 95, lineHeight),
        );
      }
      y += lineHeight;
    }

    // === 3. Scalanie PDF-ów ===
    for (final path in inputPaths) {
      final f = File(path);
      if (!await f.exists()) continue;
      try {
        final bytes = await f.readAsBytes();
        final src = PdfDocument(inputBytes: bytes);

        for (var i = 0; i < src.pages.count; i++) {
          final template = src.pages[i].createTemplate();

          if (section == null || section.pageSettings.size != template.size) {
            section = output.sections!.add();
            section.pageSettings.size = template.size;
            section.pageSettings.margins.all = 0;
          }

          section.pages.add().graphics.drawPdfTemplate(
                template,
                const Offset(0, 0),
              );
        }

        src.dispose();
      } catch (e) {
        // ignore: avoid_print
        print('PdfService: błąd przy $path: $e');
      }
    }

    if (output.sections == null || output.sections!.count <= 1) {
      output.dispose();
      return null;
    }

    final outBytes = await output.save();
    output.dispose();

    final outFile = File(outputPath);
    await outFile.create(recursive: true);
    await outFile.writeAsBytes(outBytes, flush: true);
    return outFile;
  }
}
