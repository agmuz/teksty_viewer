import 'dart:io';
import 'dart:ui' show Offset, Rect;
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfService {
  /// Scala podane pliki PDF w jeden i zapisuje w [outputPath].
  /// Na pierwszej stronie dodaje listę utworów (numer + tytuł),
  /// przeskalowaną na całą stronę.
  static Future<File?> mergePdfs({
    required List<String> inputPaths,
    required String outputPath,
    String? playlistName,
  }) async {
    if (inputPaths.isEmpty) return null;

    final output = PdfDocument();
    PdfSection? section;

    // === 1. Spis utworów (pierwsza strona — skalowany na całą) ===
    final tocSection = output.sections!.add();
    tocSection.pageSettings.size = PdfPageSize.a4;
    tocSection.pageSettings.margins.all = 30;
    final tocPage = tocSection.pages.add();
    final tocGraphics = tocPage.graphics;

    // Tytuł (nazwa playlisty) — na górze.
    var y = 0.0;
    if (playlistName?.trim().isNotEmpty == true) {
      tocGraphics.drawString(
        playlistName!.trim(),
        PdfStandardFont(
          PdfFontFamily.helvetica,
          18,
          style: PdfFontStyle.bold,
        ),
        bounds: Rect.fromLTWH(0, y, 535, 30),
      );
      y += 35;
    }

    // Skalowanie: ile linii się zmieści?
    // A4 = 842 pt wysokości, margines 30+30 = 782 pt dostępne.
    // Zostawiamy 45 pt na tytuł → 737 pt na listę.
    const availableHeight = 737.0;
    final count = inputPaths.length;
    // Wysokość linii — max 40, min 14, zależnie od liczby utworów.
    var lineHeight = count > 0 ? availableHeight / count : 20.0;
    if (lineHeight > 40) lineHeight = 40;
    if (lineHeight < 14) lineHeight = 14;
    // Rozmiar czcionki — proporcjonalny.
    var fontSize = lineHeight * 0.75;
    if (fontSize > 22) fontSize = 22;
    if (fontSize < 10) fontSize = 10;

    final fontEntry = PdfStandardFont(PdfFontFamily.helvetica, fontSize);
    final fontNumber = PdfStandardFont(
      PdfFontFamily.helvetica,
      fontSize,
      style: PdfFontStyle.bold,
    );

    for (var i = 0; i < count; i++) {
      if (y > 800) break;
      final name = inputPaths[i].split('/').last;
      final titleNoExt = name.replaceAll(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );

      tocGraphics.drawString(
        '${i + 1}.',
        fontNumber,
        bounds: Rect.fromLTWH(0, y, 40, lineHeight),
      );
      tocGraphics.drawString(
        titleNoExt,
        fontEntry,
        bounds: Rect.fromLTWH(40, y, 495, lineHeight),
      );
      y += lineHeight;
    }

    // === 2. Scalanie PDF-ów ===
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
