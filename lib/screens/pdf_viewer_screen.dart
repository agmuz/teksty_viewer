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
  final FocusNode _keyboardFocus = FocusNode();
  bool _didInitialZoom = false;
  static const double _swipeVelocity = 350.0;

  @override
  void initState() {
    super.initState();
    _index = widget.currentIndex;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _appBarVisible = false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _keyboardFocus.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  String _zoomKey(String path) => 'pdf_zoom_${path.split('/').last}';

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
      await prefs.setStringList(_zoomKey(_currentPath), vals.map((v) => v.toString()).toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Zapisano zoom dla: $_title')),
      );
    } catch (e) {
      print('Blad zapisu zoom: $e');
    }
  }

  Future<Matrix4?> _loadSavedZoom() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_zoomKey(_currentPath));
      if (list == null || list.length != 16) return null;
      final m = Matrix4.identity();
      for (var i = 0; i < 16; i++) {
        m.storage[i] = double.tryParse(list[i]) ?? 0.0;
      }
      return m;
    } catch (_) {
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

  String get _title => widget.navigationList[_index]
      .split('/')
      .last
      .replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');

  bool get _hasPrev => _index > 0;
  bool get _hasNext => _index < widget.navigationList.length - 1;
  String get _currentPath => widget.navigationList[_index];

  Future<void> _applyInitialZoom() async {
    if (_didInitialZoom) return;
    for (var i = 0; i < 40; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      try {
        final ctrl = _pdfController;
        if (!ctrl.isReady) continue;

        final saved = await _loadSavedZoom();
        if (saved != null) {
          ctrl.value = ctrl.makeMatrixInSafeRange(saved);
          _didInitialZoom = true;
          print('ZOOM: przywrocono z prefs');
          return;
        }

        final baseMatrix = ctrl.calcMatrixFitHeightForPage(pageNumber: 1);
        if (baseMatrix == null) continue;
        final baseZoom = baseMatrix.getMaxScaleOnAxis();
        final newZoom = baseZoom * 1.05;
        final m = Matrix4.identity()
          ..setEntry(0, 0, newZoom)
          ..setEntry(1, 1, newZoom)
          ..setEntry(2, 2, newZoom);
        ctrl.value = ctrl.makeMatrixInSafeRange(m);
        _didInitialZoom = true;
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

    return KeyboardListener(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          final k = event.logicalKey;
          if (k == LogicalKeyboardKey.arrowLeft ||
              k == LogicalKeyboardKey.pageUp) {
            _goPrev();
          } else if (k == LogicalKeyboardKey.arrowRight ||
              k == LogicalKeyboardKey.pageDown) {
            _goNext();
          } else if (k == LogicalKeyboardKey.escape) {
            _hideTimer?.cancel();
            Navigator.pop(context);
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _appBarVisible
            ? AppBar(
                backgroundColor: AppColors.topBar,
                foregroundColor: Colors.white,
                toolbarHeight: 96,
                title: Text(_title, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                leadingWidth: 90,
                leading: IconButton(
                  iconSize: 64,
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.arrow_back, size: 64),
                  tooltip: 'Wroc do bankow',
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new),
                    tooltip: 'Poprzedni',
                    onPressed: _hasPrev ? _goPrev : null,
                  ),
                  Center(child: Text('${_index + 1} / ${widget.navigationList.length}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white))),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios),
                    tooltip: 'Nastepny',
                    onPressed: _hasNext ? _goNext : null,
                  ),
                ],
              )
            : null,
        body: Stack(
          children: [
            Positioned.fill(
              child: isImage
                  ? PhotoView(
                      key: ValueKey('img_$_index'),
                      imageProvider: ResizeImage(FileImage(File(_currentPath)),
                          width: 2048, allowUpscaling: false),
                      minScale: PhotoViewComputedScale.contained,
                      maxScale: PhotoViewComputedScale.covered * 3.0,
                      initialScale: PhotoViewComputedScale.contained,
                      backgroundDecoration: const BoxDecoration(color: Colors.black),
                    )
                  : isText
                      ? FutureBuilder<String>(
                          future: File(_currentPath).readAsString(),
                          builder: (context, snap) {
                            if (!snap.hasData) {
                              return const Center(child: CircularProgressIndicator(color: Colors.white));
                            }
                            return SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: SelectableText(snap.data ?? '',
                                  style: const TextStyle(fontSize: 18, height: 1.4, color: Colors.white)),
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
                            panEnabled: false,
                            textSelectionParams:
                                const PdfTextSelectionParams(enabled: false),
                            annotationRenderingMode:
                                PdfAnnotationRenderingMode.none,
                            onViewerReady: (doc, ctrl) => _applyInitialZoom(),
                          ),
                        ),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _showAppBarAndHideAfter3s,
                onDoubleTap: () {
                  _hideTimer?.cancel();
                  Navigator.pop(context);
                },
                onLongPress: _saveZoomForCurrentFile,
                onHorizontalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v >= _swipeVelocity) _goPrev();
                  if (v <= -_swipeVelocity) _goNext();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
