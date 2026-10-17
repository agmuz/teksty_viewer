import 'package:flutter/material.dart';
import '../utils/colors.dart';

class PdfTile extends StatelessWidget {
  final String fileName;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool played;
  final bool buildMode;
  final int? orderNumber;
  /// Wysokość kafelka — skalowanie czcionki i ikon.
  final double tileHeight;
  /// Tryb edycji playlisty (drag & drop).
  final bool editMode;
  /// Indeks kafelka (dla drag & drop).
  final int index;
  /// Pozycja w playliście (1..N) — pokazywana w editMode.
  final int? position;
  /// Callback przenoszenia (drag & drop).
  final void Function(int from, int to)? onMove;

  const PdfTile({
    super.key,
    required this.fileName,
    required this.onTap,
    this.onLongPress,
    this.played = false,
    this.buildMode = false,
    this.orderNumber,
    this.tileHeight = 60,
    this.editMode = false,
    this.index = 0,
    this.position,
    this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    // Skalowanie z wysokości kafelka.
    final fontSizeTitle = (tileHeight * 0.55).clamp(14.0, 40.0);
    final circleSize = (tileHeight * 0.65).clamp(28.0, 60.0);
    final fontSizeCircle = (tileHeight * 0.42).clamp(12.0, 30.0);
    final hPad = (tileHeight * 0.12).clamp(6.0, 16.0);
    final vPad = (tileHeight * 0.08).clamp(2.0, 12.0);

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
      bgColor = AppColors.tileSelected;
    } else if (played) {
      bgColor = AppColors.tilePlayed;
    } else {
      bgColor = AppColors.tileDefault;
    }

    // Kółko pokazuje: pozycję (editMode) LUB numer zamówienia (buildMode).
    final showPosition = editMode && position != null;
    final showOrder = selected;

    final inner = Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        onLongPress: editMode ? null : onLongPress,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
          child: Row(
            children: [
              if (showPosition)
                Container(
                  width: circleSize,
                  height: circleSize,
                  alignment: Alignment.center,
                  margin: EdgeInsets.only(right: hPad * 0.8),
                  decoration: const BoxDecoration(
                    color: Colors.black87,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$position',
                    style: TextStyle(
                      fontSize: fontSizeCircle,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                )
              else if (showOrder)
                Container(
                  width: circleSize,
                  height: circleSize,
                  alignment: Alignment.center,
                  margin: EdgeInsets.only(right: hPad * 0.8),
                  decoration: const BoxDecoration(
                    color: Colors.black87,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$orderNumber',
                    style: TextStyle(
                      fontSize: fontSizeCircle,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: fontSizeTitle,
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

    // Drag & drop tylko w editMode.
    if (!editMode || onMove == null) return inner;

    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != index,
      onAcceptWithDetails: (d) => onMove!(d.data, index),
      builder: (context, candidate, rejected) {
        final highlight = candidate.isNotEmpty;
        return LongPressDraggable<int>(
          data: index,
          feedback: SizedBox(
            width: 300,
            height: tileHeight,
            child: Material(
              color: Colors.transparent,
              child: Opacity(opacity: 0.7, child: inner),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: inner),
          child: highlight
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 3),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: inner,
                )
              : inner,
        );
      },
    );
  }
}
