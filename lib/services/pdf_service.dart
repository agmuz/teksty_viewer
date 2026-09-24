import 'dart:io';
import 'dart:ui' show Offset;
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfService {
  /// Scala podane pliki PDF w jeden i zapisuje w [outputPath].
  static Future<File?> mergePdfs({
    required List<String> inputPaths,
    required String outputPath,
  }) async {
    if (inputPaths.isEmpty) return null;

    final output = PdfDocument();
    PdfSection? section;

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

    if (output.sections == null || output.sections!.count == 0) {
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
