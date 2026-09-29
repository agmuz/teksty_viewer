import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/colors.dart';

class PdfViewerScreen extends StatefulWidget {
  final String filePath;
  final List<String> navigationList;
  final int currentIndex;
  final Future<void> Function(String newPath)? onFileChanged;

  const PdfViewerScreen({
    super.key,
    required this.filePath,
    required this.navigationList,
    required this.currentIndex,
    this.onFileChanged,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late int _index;
  bool _appBarVisible = true;
  Timer? _hideTimer;
  final PdfViewerController _pdfController = PdfViewerController();
  bool _didInitialZoom = false;
  static const double _swipeVelocity = 350.0;

  @override
  void initState() {
    super.initState();
    _index = widget.currentIndex;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Ukryj AppBar po 3 sekundach
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _appBarVisible = false);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  /// Klucz do SharedPreferences dla danego pliku PDF.
  String _zoomKey(String path) {
    final name = path.split('/').last;
    return 'pdf_zoom_$name';
  }

  /// Zapisuje aktualna macierz PDF dla biezacego pliku.
  Future<void> _saveZoomForCurrentFile() async {
    if (!_pdfController.isReady) return;
    try {
      final m = _pdfController.value;

      final vals = <double>[
        m.storage[0], m.storage[1], m.storage[2], m.storage[3],
        m.storage[4], m.storage[5], m.storage[6], m.storage[7],
        m.storage[8], m.storage[9], m.storage[10], m.storage[11],
        m.storage[12], m.storage[13], m.storage[14], m.storage[15],
      ];

      final prefs = await SharedPreferences.getInstance();
      final key = _zoomKey(_currentPath);
      await prefs.setStringList(key, vals.map((v) => v.toString()).toList());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Zapisano zoom dla: $_title')),
      );
    } catch (e) {
      print('Blad zapisu zoom: $e');
    }
  }

  /// Zwraca zapisana macierz jesli istnieje.
  Future<Matrix4?> _loadSavedZoom() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _zoomKey(_currentPath);
      final list = prefs.getStringList(key);
      if (list == null || list.length != 16) return null;

      final vals = list.map((s) => double.tryParse(s) ?? 0.0).toList();
      final m = Matrix4.identity();
      for (var i = 0; i < 16; i++) {
        m.storage[i] = vals[i];
      }
      return m;
    } catch (e) {
      print('Blad odczytu zoom: $e');
      return null;
    }
  }

  void _showAppBarAndHideAfter3s() {
    _hideTimer?.cancel();
    setState(() => _appBarVisible = true);
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _appBarVisible = false);
    });
  }

  Future<void> _goTo(int newIndex) async {
    if (newIndex < 0 || newIndex >= widget.navigationList.length) return;
    if (newIndex == _index) return;
    final newPath = widget.navigationList[newIndex];
    setState(() {
      _index = newIndex;
      _didInitialZoom = false;
    });
    await widget.onFileChanged?.call(newPath);
  }

  Future<void> _goPrev() => _goTo(_index - 1);
  Future<void> _goNext() => _goTo(_index + 1);

  String get _title {
    final p = widget.navigationList[_index];
    return p
        .split('/')
        .last
        .replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
  }

  bool get _hasPrev => _index > 0;
  bool get _hasNext => _index < widget.navigationList.length - 1;
  String get _currentPath => widget.navigationList[_index];

  /// Ustawia zoom na fit-height * 1.05 i pozycje na LEWY GORNY rog strony.
  Future<void> _applyInitialZoom() async {
    if (_didInitialZoom) return;
    // Poczekaj az pdfrx zaladuje dokument
    for (var i = 0; i < 40; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      try {
        final ctrl = _pdfController;
        if (!ctrl.isReady) continue;

        // 1) Sprawdz, czy jest zapisany zoom dla tego pliku
        final saved = await _loadSavedZoom();
        if (saved != null) {
          ctrl.value = ctrl.makeMatrixInSafeRange(saved);
          _didInitialZoom = true;
          print('ZOOM: przywrocono z prefs');
          return;
        }

        // 2) Brak zapisu — domyslny fit-height * 1.05
        // Macierz dla strony 1 z anchorem na gorze-lewo
        final baseMatrix = ctrl.calcMatrixFitHeightForPage(pageNumber: 1);
        if (baseMatrix == null) continue;

        // Wyciagnij zoom (skala Z) z macierzy
        final baseZoom = baseMatrix.getMaxScaleOnAxis();
        // Dodaj 5%
        final newZoom = baseZoom * 1.05;

        // Ustaw macierz: zoom * 1.05, pozycja na (0,0) = lewy gorny ekranu
        final m = Matrix4.identity()
          ..setEntry(0, 0, newZoom)
          ..setEntry(1, 1, newZoom)
          ..setEntry(2, 2, newZoom)
          ..setEntry(0, 3, 0.0)  // dx = 0 → lewa krawedz strony = lewa krawedz ekranu
          ..setEntry(1, 3, 0.0); // dy = 0 → gora strony = gora ekranu

        ctrl.value = ctrl.makeMatrixInSafeRange(m);
        _didInitialZoom = true;
        print('ZOOM: base=$baseZoom, new=$newZoom');
        return;
      } catch (e) {
        print('ZOOM blad: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _currentPath.toLowerCase();
    final isImage = p.endsWith('.png') ||
        p.endsWith('.jpg') ||
        p.endsWith('.jpeg') ||
        p.endsWith('.webp') ||
        p.endsWith('.gif') ||
        p.endsWith('.bmp');
    final isText = p.endsWith('.txt') || p.endsWith('.md');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _appBarVisible
          ? AppBar(
              backgroundColor: AppColors.topBar,
              foregroundColor: Colors.white,
              toolbarHeight: 64,
              title: Text(
                _title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w600),
              ),
              leading: IconButton(
                iconSize: 32,
                padding: const EdgeInsets.all(8),
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Lista',
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  iconSize: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  icon: const Icon(Icons.arrow_back_ios_new),
                  tooltip: 'Poprzedni',
                  onPressed: _hasPrev ? _goPrev : null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Center(
                    child: Text(
                      '${_index + 1} / ${widget.navigationList.length}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  iconSize: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  icon: const Icon(Icons.arrow_forward_ios),
                  tooltip: 'Następny',
                  onPressed: _hasNext ? _goNext : null,
                ),
              ],
            )
          : null,
      body: Stack(
        children: [
          // Treść (PDF / obraz / tekst)
          Positioned.fill(
            child: isImage
                ? PhotoView(
                    key: ValueKey('img_$_index'),
                    imageProvider: ResizeImage(
                      FileImage(File(_currentPath)),
                      width: 2048,
                      allowUpscaling: false,
                    ),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 3.0,
                    initialScale: PhotoViewComputedScale.contained,
                    backgroundDecoration:
                        const BoxDecoration(color: Colors.black),
                  )
                : isText
                    ? FutureBuilder<String>(
                        future: File(_currentPath).readAsString(),
                        builder: (context, snap) {
                          if (snap.connectionState !=
                              ConnectionState.done) {
                            return const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.white),
                            );
                          }
                          if (snap.hasError) {
                            return Center(
                              child: Text(
                                'Nie można odczytać pliku:\n${snap.error}',
                                style:
                                    const TextStyle(color: Colors.white),
                              ),
                            );
                          }
                          return SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: SelectableText(
                              snap.data ?? '',
                              style: const TextStyle(
                                fontSize: 18,
                                height: 1.4,
                                color: Colors.white,
                              ),
                            ),
                          );
                        },
                      )
                    : PdfViewer.file(
                        _currentPath,
                        key: ValueKey('pdf_$_index'),
                        controller: _pdfController,
                        params: PdfViewerParams(
                          margin: 0,
                          maxScale: 8.0,
                          onViewerReady: (doc, ctrl) {
                            _applyInitialZoom();
                          },
                        ),
                      ),
          ),

          // ── PACNIĘCIE W ŚRODEK → pokaż AppBar ────────────────────────
          // ── PODWÓJNE PACNIĘCIE → powrót do kafelków ─────────────────
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _showAppBarAndHideAfter3s,
              onDoubleTap: () {
                _hideTimer?.cancel();
                Navigator.pop(context);
              },
              onLongPress: () {
                _saveZoomForCurrentFile();
              },
            ),
          ),

          // ── SWIPE Z LEWEJ KRAWĘDZI → poprzedni ───────────────────────
          Positioned(
            left: 0,
            top: 80,
            bottom: 40,
            width: 60,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v >= _swipeVelocity) _goPrev();
              },
            ),
          ),

          // ── SWIPE Z PRAWEJ KRAWĘDZI → następny ───────────────────────
          Positioned(
            right: 0,
            top: 80,
            bottom: 40,
            width: 60,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v <= -_swipeVelocity) _goNext();
              },
            ),
          ),
        ],
      ),
    );
  }
}
