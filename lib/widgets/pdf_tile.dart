import 'package:flutter/material.dart';
import '../utils/colors.dart';

class PdfTile extends StatelessWidget {
  final String fileName;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool played;
  final bool buildMode;
  final int? orderNumber;

  const PdfTile({
    super.key,
    required this.fileName,
    required this.onTap,
    this.onLongPress,
    this.played = false,
    this.buildMode = false,
    this.orderNumber,
  });

  @override
  Widget build(BuildContext context) {
    // Tytuł = nazwa pliku bez .pdf, przycięta do 30 znaków
    var title = fileName.replaceAll(
      RegExp(r'\.pdf$', caseSensitive: false),
      '',
    );
    if (title.length > 30) {
      title = title.substring(0, 30);
    }

    final selected = orderNumber != null && buildMode;

    Color bgColor;
    if (selected) {
      bgColor = AppColors.tileSelected; // żółty
    } else if (played) {
      bgColor = AppColors.tilePlayed; // piaskowy
    } else {
      bgColor = AppColors.tileDefault; // jasnoniebieski
    }

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Row(
            children: [
              // Kółko z numerem — tylko w trybie budowania playlisty i gdy zaznaczone
              if (selected)
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: Colors.black87,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$orderNumber',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              // Tytuł
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
