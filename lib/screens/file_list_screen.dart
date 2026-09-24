import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../models/playlist.dart';
import '../services/pref_service.dart';
import '../services/pdf_service.dart';
import '../utils/colors.dart';
import '../widgets/pdf_tile.dart';
import 'pdf_viewer_screen.dart';

class FileListScreen extends StatefulWidget {
  const FileListScreen({super.key});

  @override
  State<FileListScreen> createState() => _FileListScreenState();
}

class _FileListScreenState extends State<FileListScreen>
    with WidgetsBindingObserver {
  List<File> _files = [];
  List<File> _filteredFiles = [];
  List<Playlist> _playlists = [];
  bool _loading = true;
  String _status = 'Ładowanie...';
  String? _folderPath;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _playlistNameController =
      TextEditingController();

  bool _searchOpen = false;
  bool _buildMode = false;
  Playlist? _editingPlaylist;
  List<String> _selectedFileNames = [];

  String? _activePlaylistId;
  Map<String, List<String>> _playedByPlaylist = {};

  static const _playedAllKey = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _playlistNameController.dispose();
    super.dispose();
  }

  @override
    @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _defaultAppDir().then((dir) => _scanFolder(dir));
    }
  }

  String get _currentPlayedKey => _activePlaylistId ?? _playedAllKey;

          Future<void> _init() async {
    _playlists = await PrefService.loadPlaylists();
    _playedByPlaylist = await PrefService.loadPlayed();

    // ZAWSZE folder wewnętrzny apki: Documents/teksty
    final dir = await _defaultAppDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _folderPath = dir.path;
    await _scanFolder(dir);
  }

  Future<Directory> _defaultAppDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/teksty');
  }

      
  Future<void> _importPdfs() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'pdf',
        'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp',
        'txt', 'md',
      ],
    );
    if (files.isEmpty) return;

    // Zawsze zapisujemy do piaskownicy apki - tam mamy prawo zapisu
    final targetDir = await _defaultAppDir();
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    _folderPath = targetDir.path;
    await PrefService.saveFolderPath(targetDir.path);

    var copied = 0;
    for (final f in files) {
      try {
        final bytes = await f.readAsBytes();
        final out = File('${targetDir.path}/${f.name}');
        await out.writeAsBytes(bytes);
        copied++;
        debugPrint('Skopiowano: ${f.name} (${bytes.length} B)');
      } catch (e) {
        debugPrint('Nie udało się skopiować ${f.name}: $e');
      }
    }

    await _scanFolder(targetDir);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dodano $copied plików')),
      );
    }
  }

  Future<void> _scanFolder(Directory dir) async {
    setState(() {
      _loading = true;
      _status = 'Skanowanie...';
    });

    try {
      // Skanuj oba foldery (główny + extra), jeśli istnieją

      final entries = await dir.list().toList();
      final pdfs = entries.whereType<File>().where((f) {
        final n = f.path.toLowerCase();
        return n.endsWith('.pdf') ||
            n.endsWith('.png') ||
            n.endsWith('.jpg') ||
            n.endsWith('.jpeg') ||
            n.endsWith('.webp') ||
            n.endsWith('.gif') ||
            n.endsWith('.bmp') ||
            n.endsWith('.txt') ||
            n.endsWith('.md');
      }).toList();
      pdfs.sort((a, b) {
        final an = a.path.split('/').last.toLowerCase();
        final bn = b.path.split('/').last.toLowerCase();
        return an.compareTo(bn);
      });
      setState(() {
        _files = pdfs;
        _filteredFiles = pdfs;
        _loading = false;
        _status = '${pdfs.length} plików';
      });
      _applyFilter();
    } catch (e) {
      setState(() {
        _loading = false;
        _status = 'Błąd skanowania: $e';
      });
    }
  }

  void _applyFilter() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      var base = _files;
      if (_activePlaylistId != null) {
        final pl = _playlists.firstWhere(
          (p) => p.id == _activePlaylistId,
          orElse: () => Playlist(id: '', name: '', fileNames: []),
        );
        base = _files
            .where((f) => pl.fileNames.contains(f.path.split('/').last))
            .toList();
        final order = {
          for (var i = 0; i < pl.fileNames.length; i++) pl.fileNames[i]: i
        };
        base.sort((a, b) {
          final an = a.path.split('/').last;
          final bn = b.path.split('/').last;
          return (order[an] ?? 9999).compareTo(order[bn] ?? 9999);
        });
      }
      _filteredFiles = query.isEmpty
          ? base
          : base.where((f) => f.path.toLowerCase().contains(query)).toList();
    });
  }

  Future<void> _markAsPlayed(String fileName) async {
    final key = _currentPlayedKey;
    final list = _playedByPlaylist[key] ?? [];
    if (!list.contains(fileName)) {
      list.add(fileName);
      _playedByPlaylist[key] = list;
      await PrefService.savePlayed(_playedByPlaylist);
      if (mounted) setState(() {});
    }
  }

  Future<void> _openPdf(File file, {int? index}) async {
    final fileName = file.path.split('/').last;
    await _markAsPlayed(fileName);
    if (!mounted) return;

    final navigationList = List<File>.from(_filteredFiles);
    final currentIndex =
        index ?? navigationList.indexWhere((f) => f.path == file.path);
    final safeIndex = currentIndex < 0 ? 0 : currentIndex;

    Future<void> onFileChanged(String newPath) async {
      await _markAsPlayed(newPath.split('/').last);
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(
          filePath: file.path,
          navigationList: navigationList.map((f) => f.path).toList(),
          currentIndex: safeIndex,
          onFileChanged: onFileChanged,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _generatePlaylistPdf(Playlist pl) async {
    if (pl.fileNames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Playlista jest pusta')),
      );
      return;
    }

    final dir = _folderPath != null
        ? Directory(_folderPath!)
        : await _defaultAppDir();

    // Zbierz ścieżki plików w kolejności z playlisty
    final paths = <String>[];
    final missing = <String>[];
    for (final name in pl.fileNames) {
      final f = File('${dir.path}/$name');
      if (await f.exists()) {
        paths.add(f.path);
      } else {
        missing.add(name);
      }
    }

    if (paths.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Brak plików z playlisty na dysku')),
      );
      return;
    }

    // Pokaż loader
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final docs = await getApplicationDocumentsDirectory();
      final safeName = pl.name.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
      final outPath = '${docs.path}/$safeName.pdf';

      final outFile = await PdfService.mergePdfs(
        inputPaths: paths,
        outputPath: outPath,
      );

      // Zamknij loader
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (outFile == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nie udało się wygenerować PDF')),
        );
        return;
      }

      if (!mounted) return;
      if (missing.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pominięto ${missing.length} brakujących plików')),
        );
      }

      // Otwórz systemowe okno udostępniania (tam: Drukuj / Zapisz / Wyślij)
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(outFile.path, mimeType: 'application/pdf')],
          subject: pl.name,
          text: 'Playlista: ${pl.name}',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Błąd: $e')),
      );
    }
  }

  Future<void> _deleteAllFiles() async {
    final dir = _folderPath != null
        ? Directory(_folderPath!)
        : await _defaultAppDir();

    if (!await dir.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Folder nie istnieje')),
      );
      return;
    }

    final allFiles = await dir
        .list()
        .where((e) {
      if (e is! File) return false;
      final n = e.path.toLowerCase();
      return n.endsWith('.pdf') ||
          n.endsWith('.png') ||
          n.endsWith('.jpg') ||
          n.endsWith('.jpeg') ||
          n.endsWith('.webp') ||
          n.endsWith('.gif') ||
          n.endsWith('.bmp') ||
          n.endsWith('.txt') ||
          n.endsWith('.md');
    })
        .cast<File>()
        .toList();

    if (allFiles.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Brak plików do usunięcia')),
      );
      return;
    }

    if (!mounted) return;
    final n = allFiles.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Usunąć wszystkie pliki?'),
        content: Text(
            'Zostanie trwale usuniętych $n plików z folderu.\n'
            'Playlisty i oznaczenia zostaną wyczyszczone.\n\n'
            'Tej operacji nie można cofnąć.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Usuń wszystko',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    var removed = 0;
    for (final f in allFiles) {
      try {
        if (await f.exists()) {
          await f.delete();
          removed++;
        }
      } catch (e) {
        debugPrint('Błąd usuwania ${f.path}: $e');
      }
    }

    // wyczyść playlisty i oznaczenia
    setState(() {
      _playlists = _playlists
          .map((p) => Playlist(id: p.id, name: p.name, fileNames: []))
          .toList();
      _playedByPlaylist = _playedByPlaylist.map((k, v) => MapEntry(k, []));
    });
    await PrefService.savePlaylists(_playlists);
    await PrefService.savePlayed(_playedByPlaylist);

    await _scanFolder(dir);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Usunięto $removed plików')),
    );
  }

  Future<void> _deleteFile(File file) async {
    final fileName = file.path.split('/').last;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usunąć plik?'),
        content: Text('Plik "$fileName" zostanie trwale usunięty.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Usuń',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      if (await file.exists()) await file.delete();
      setState(() {
        _playlists = _playlists
            .map((p) => Playlist(
                  id: p.id,
                  name: p.name,
                  fileNames:
                      p.fileNames.where((n) => n != fileName).toList(),
                ))
            .toList();
        _playedByPlaylist = _playedByPlaylist.map(
          (k, v) => MapEntry(k, v.where((n) => n != fileName).toList()),
        );
      });
      await PrefService.savePlaylists(_playlists);
      await PrefService.savePlayed(_playedByPlaylist);

      if (_folderPath != null) {
        await _scanFolder(Directory(_folderPath!));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Usunięto: $fileName')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Błąd usuwania: $e')));
    }
  }

  void _startNewPlaylist() {
    setState(() {
      _buildMode = true;
      _editingPlaylist = null;
      _selectedFileNames = [];
      _playlistNameController.text = '';
      _activePlaylistId = null;
      _applyFilter();
    });
  }

  void _startEditPlaylist(Playlist pl) {
    setState(() {
      _buildMode = true;
      _editingPlaylist = pl;
      _selectedFileNames = List.from(pl.fileNames);
      _playlistNameController.text = pl.name;
      _activePlaylistId = null;
      _applyFilter();
    });
  }

  void _toggleSelection(File file) {
    final name = file.path.split('/').last;
    setState(() {
      if (_selectedFileNames.contains(name)) {
        _selectedFileNames.remove(name);
      } else {
        _selectedFileNames.add(name);
      }
    });
  }

  Future<void> _saveBuildPlaylist() async {
    final name = _playlistNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Podaj nazwę playlisty')),
      );
      return;
    }
    if (_selectedFileNames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wybierz co najmniej jeden utwór')),
      );
      return;
    }
    setState(() {
      if (_editingPlaylist != null) {
        final idx = _playlists.indexWhere((p) => p.id == _editingPlaylist!.id);
        if (idx >= 0) {
          _playlists[idx] = Playlist(
            id: _editingPlaylist!.id,
            name: name,
            fileNames: List.from(_selectedFileNames),
          );
        }
      } else {
        _playlists.add(Playlist(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: name,
          fileNames: List.from(_selectedFileNames),
        ));
      }
    });
    await PrefService.savePlaylists(_playlists);
    if (!mounted) return;
    setState(() {
      _buildMode = false;
      _editingPlaylist = null;
      _selectedFileNames = [];
      _playlistNameController.text = '';
      _applyFilter();
    });
  }

  void _cancelBuild() {
    setState(() {
      _buildMode = false;
      _editingPlaylist = null;
      _selectedFileNames = [];
      _playlistNameController.text = '';
    });
  }

  void _openPlaylist(Playlist pl) {
    setState(() {
      _activePlaylistId = pl.id;
      _searchController.clear();
      _applyFilter();
    });
  }

  void _closePlaylist() {
    setState(() {
      _activePlaylistId = null;
      _applyFilter();
    });
  }

  Future<void> _showPlaylistMenu(Playlist pl) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                pl.name,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('Otwórz playlistę'),
              onTap: () => Navigator.pop(ctx, 'open'),
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edytuj playlistę'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services),
              title: const Text('Wyczyść oznaczenia'),
              onTap: () => Navigator.pop(ctx, 'clear'),
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                'Usuń playlistę',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'open') _openPlaylist(pl);
    if (action == 'edit') _startEditPlaylist(pl);
    if (action == 'clear') await _clearPlayed(pl.id);
    if (action == 'delete') await _deletePlaylist(pl);
  }

  Future<void> _clearPlayed(String key) async {
    setState(() => _playedByPlaylist[key] = []);
    await PrefService.savePlayed(_playedByPlaylist);
  }

  Future<void> _clearCurrentPlayed() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wyczyścić oznaczenia?'),
        content: const Text(
            'Wszystkie piaskowe kafelki wrócą do niebieskiego.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Wyczyść'),
          ),
        ],
      ),
    );
    if (confirm == true) await _clearPlayed(_currentPlayedKey);
  }

  Future<void> _deletePlaylist(Playlist pl) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usunąć playlistę?'),
        content: Text('Playlista "${pl.name}" zostanie usunięta.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Usuń',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() {
        _playlists.removeWhere((p) => p.id == pl.id);
        _playedByPlaylist.remove(pl.id);
        if (_activePlaylistId == pl.id) _activePlaylistId = null;
      });
      await PrefService.savePlaylists(_playlists);
      await PrefService.savePlayed(_playedByPlaylist);
    }
  }

  int? _selectionOrder(String fileName) {
    final idx = _selectedFileNames.indexOf(fileName);
    return idx >= 0 ? idx + 1 : null;
  }

  bool _isPlayed(String fileName) =>
      (_playedByPlaylist[_currentPlayedKey] ?? []).contains(fileName);

  bool get _hasPlayedInCurrent =>
      (_playedByPlaylist[_currentPlayedKey] ?? []).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final activePlaylist = _activePlaylistId != null
        ? _playlists.firstWhere(
            (p) => p.id == _activePlaylistId,
            orElse: () => Playlist(id: '', name: '', fileNames: []),
          )
        : null;

    return Scaffold(
      body: SafeArea(
        child: _loading
            ? Center(child: Text(_status))
            : _folderPath == null
                ? _buildNoFolderView()
                : _files.isEmpty
                    ? _buildEmptyView()
                    : Column(
                        children: [
                          _buildTopBar(activePlaylist),
                          if (_searchOpen) _buildSearchField(),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final isLandscape = constraints.maxWidth >
                                    constraints.maxHeight;
                                final cols = isLandscape ? 4 : 2;
                                return GridView.builder(
                                  padding: const EdgeInsets.all(4),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: cols,
                                    crossAxisSpacing: 6,
                                    mainAxisSpacing: 4,
                                    childAspectRatio:
                                        isLandscape ? 4.3 : 5.9,
                                  ),
                                  itemCount: _filteredFiles.length,
                                  itemBuilder: (context, index) {
                                    final file = _filteredFiles[index];
                                    final fileName =
                                        file.path.split('/').last;
                                    return PdfTile(
                                      fileName: fileName,
                                      played: _isPlayed(fileName),
                                      buildMode: _buildMode,
                                      orderNumber: _selectionOrder(fileName),
                                      onTap: () {
                                        if (_buildMode) {
                                          _toggleSelection(file);
                                        } else {
                                          _openPdf(file, index: index);
                                        }
                                      },
                                      onLongPress: () => _deleteFile(file),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                          if (_buildMode) _buildBuildBar(),
                        ],
                      ),
      ),
    );
  }

  Widget _buildNoFolderView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.folder_open,
              size: 64, color: AppColors.tileDefault),
          const SizedBox(height: 16),
          Text(_status),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _importPdfs,
            icon: const Icon(Icons.folder),
            label: const Text('Wybierz folder'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _importPdfs,
            icon: const Icon(Icons.add),
            label: const Text('Dodaj pliki'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(_status),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _importPdfs,
            icon: const Icon(Icons.add),
            label: const Text('Dodaj pliki'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _importPdfs,
            child: const Text('Zmień folder'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Szukaj po tytule...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () {
              _searchController.clear();
              setState(() => _searchOpen = false);
            },
          ),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildTopBar(Playlist? activePlaylist) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: AppColors.topBar,
      child: Row(
        children: [
          if (_activePlaylistId != null)
            IconButton(
              icon: const Icon(Icons.arrow_back,
                  color: Colors.white, size: 22),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: 'Wróć',
              onPressed: _closePlaylist,
            ),
          if (_activePlaylistId == null && _playlists.isNotEmpty)
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _playlists.length,
                itemBuilder: (context, index) {
                  final pl = _playlists[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onLongPress: () => _showPlaylistMenu(pl),
                      child: ActionChip(
                        avatar:
                            const Icon(Icons.queue_music, size: 16),
                        label: Text(
                            '${pl.name} (${pl.fileNames.length})'),
                        onPressed: () => _openPlaylist(pl),
                      ),
                    ),
                  );
                },
              ),
            )
          else if (_activePlaylistId != null)
            Expanded(
              child: Text(
                activePlaylist?.name ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Expanded(
              child: Text(
                'Teksty',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '${_filteredFiles.length}',
              style:
                  const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          IconButton(
            icon: Icon(
              _searchOpen ? Icons.search_off : Icons.search,
              color: Colors.white,
              size: 22,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: 'Szukaj',
            onPressed: () =>
                setState(() => _searchOpen = !_searchOpen),
          ),
          if (!_buildMode && _activePlaylistId == null)
            IconButton(
              icon: const Icon(Icons.add, color: Colors.white, size: 22),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: 'Nowa playlista',
              onPressed: _startNewPlaylist,
            ),
          if (_activePlaylistId != null && !_buildMode)
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white, size: 22),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: 'Edytuj playlistę',
              onPressed: () {
                final pl = _playlists
                    .firstWhere((p) => p.id == _activePlaylistId);
                _startEditPlaylist(pl);
              },
            ),
          if (_activePlaylistId != null && !_buildMode)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf,
                  color: Colors.white, size: 22),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: 'Wygeneruj PDF',
              onPressed: () {
                final pl = _playlists
                    .firstWhere((p) => p.id == _activePlaylistId);
                _generatePlaylistPdf(pl);
              },
            ),
          if (_hasPlayedInCurrent && !_buildMode)
            IconButton(
              icon: const Icon(Icons.cleaning_services,
                  color: Colors.white, size: 22),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: 'Czyść listę',
              onPressed: _clearCurrentPlayed,
            ),
          if (_files.isNotEmpty && !_buildMode)
            IconButton(
              icon: const Icon(Icons.delete_sweep,
                  color: Colors.redAccent, size: 22),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: 'Usuń wszystko',
              onPressed: _deleteAllFiles,
            ),
          IconButton(
            icon: const Icon(Icons.folder_open,
                color: Colors.white, size: 22),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: 'Zmień folder',
            onPressed: _importPdfs,
          ),
        ],
      ),
    );
  }

  Widget _buildBuildBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.black87,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _playlistNameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Nazwa playlisty',
                  hintStyle: TextStyle(color: Colors.white54),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white54),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: _cancelBuild,
              tooltip: 'Anuluj',
            ),
            IconButton(
              icon: const Icon(Icons.save, color: Colors.green),
              onPressed: _saveBuildPlaylist,
              tooltip: 'Zapisz',
            ),
          ],
        ),
      ),
    );
  }
}
