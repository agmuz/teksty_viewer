import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:saf/saf.dart';
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
  String _activeBank = 'kapela1';
  String? _previousBank;
  List<String> _banks = [];
  Map<String, String> _bankUris = {};
  final Saf _saf = Saf();

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
    _banks = await PrefService.loadBanks();
    _bankUris = await PrefService.loadBankUris();
    _activeBank = await PrefService.loadActiveBank();
    if (!_banks.contains(_activeBank) && _banks.isNotEmpty) {
      _activeBank = _banks.first;
    }
    _playlists = await PrefService.loadPlaylists(_activeBank);
    _playedByPlaylist = await PrefService.loadPlayed(_activeBank);

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
    return Directory('${docs.path}/teksty/$_activeBank');
  }

      
  Future<void> _importPdfs() async {
    // Zamiast FilePicker — używamy SAF (Dysk Google) i wywołujemy _setBankUri,
    // żeby bank automatycznie przyjął nazwę folderu (jeśli ma domyślną).
    await _setBankUri(_activeBank);
  }

  /// Wskazanie folderu źródłowego (Dysk Google) dla banku + od razu kopiowanie.
  /// Nazwa banku zostaje automatycznie zmieniona na nazwę folderu z Dysku Google
  /// (jeśli bank ma nazwę domyślną bank1..bank5 albo pustą).
  Future<void> _setBankUri(String bank) async {
    debugPrint('SETBANK START: bank=$bank');
    SafDocumentFile? dir;
    try {
      dir = await _saf.pickDirectory();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Błąd wyboru folderu: $e')),
      );
      return;
    }
    if (dir == null) {
      debugPrint('SETBANK: user cancelled');
      return;
    }
    debugPrint('SETBANK: dir.name="${dir.name}", dir.uri="${dir.uri}"');

    // Wyciągnij nazwę folderu z Dysku Google
    final folderName = dir.name.trim();

    // Sprawdź czy bank ma nazwę domyślną (bank1..bank5)
    final isDefaultName = RegExp(r'^bank\d+$').hasMatch(bank);
    final shouldRename = folderName.isNotEmpty &&
        isDefaultName &&
        folderName != bank;

    var effectiveBank = bank;

    if (shouldRename) {
      // Nowa nazwa — sprawdź kolizje
      var newName = folderName;
      var counter = 2;
      while (_banks.contains(newName) && newName != bank) {
        newName = '$folderName ($counter)';
        counter++;
      }

      try {
        // Zmień nazwę katalogu lokalnego
        final currentDir = await _defaultAppDir();
        final oldDir = Directory('${currentDir.parent.path}/$bank');
        final newDir = Directory('${currentDir.parent.path}/$newName');
        if (await oldDir.exists() && !await newDir.exists()) {
          await oldDir.rename(newDir.path);
        }

        // Przenieś playlisty i oznaczenia
        final pl = await PrefService.loadPlaylists(bank);
        final played = await PrefService.loadPlayed(bank);
        await PrefService.savePlaylists(newName, pl);
        await PrefService.savePlayed(newName, played);
        await PrefService.clearBankData(bank);

        // Przenieś URI
        _bankUris.remove(bank);
        _bankUris[newName] = dir.uri;
        await PrefService.saveBankUris(_bankUris);

        // Zaktualizuj listę banków W PAMIĘCI, potem zapisz
        setState(() {
          final idx = _banks.indexOf(bank);
          if (idx >= 0) _banks[idx] = newName;
        });
        await PrefService.saveBanks(_banks);

        // Jeśli to był aktywny bank — zaktualizuj
        if (_activeBank == bank) {
          setState(() {
            _activeBank = newName;
          });
          await PrefService.saveActiveBank(newName);
        }

        effectiveBank = newName;
        debugPrint('SETBANK Bank "$bank" -> "$newName"');
      } catch (e) {
        debugPrint('Błąd zmiany nazwy banku: $e');
      }
    } else {
      // Nie zmieniamy nazwy — tylko zapisz URI
      _bankUris[bank] = dir.uri;
      await PrefService.saveBankUri(bank, dir.uri);
    }

    // Przeładuj listę banków z PrefService i wymuś odświeżenie UI
    _banks = await PrefService.loadBanks();
    if (!mounted) return;
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Wybrano folder dla "$effectiveBank" — kopiuję pliki...',
        ),
      ),
    );

    await _refreshFromBankUri(effectiveBank);
  }

  /// Kopiuje nowe pliki z folderu źródłowego (Dysk Google) do lokalnego banku.
  /// Pomija pliki już istniejące lokalnie.
  Future<void> _refreshFromBankUri(String bank) async {
    final uri = _bankUris[bank];
    if (uri == null || uri.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bank "$bank" nie ma wskazanego folderu źródłowego')),
      );
      return;
    }

    List<SafDocumentFile> files;
    try {
      files = await _saf.list(uri);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Błąd listowania folderu: $e')),
      );
      return;
    }

    final docs = await getApplicationDocumentsDirectory();
    final localDir = Directory('${docs.path}/teksty/$bank');
    if (!await localDir.exists()) {
      await localDir.create(recursive: true);
    }

    var copied = 0;
    var skipped = 0;
    var errors = 0;

    for (final f in files) {
      // Pomiń podfoldery (na razie — tylko pliki z głównego katalogu)
      if (f.isDir) continue;

      // Obsługiwane rozszerzenia
      final name = f.name.toLowerCase();
      final isSupported = name.endsWith('.pdf') ||
          name.endsWith('.png') ||
          name.endsWith('.jpg') ||
          name.endsWith('.jpeg') ||
          name.endsWith('.webp') ||
          name.endsWith('.gif') ||
          name.endsWith('.bmp') ||
          name.endsWith('.txt') ||
          name.endsWith('.md');
      if (!isSupported) continue;

      final localFile = File('${localDir.path}/${f.name}');
      if (await localFile.exists()) {
        skipped++;
        continue;
      }

      try {
        final bytes = await _saf.readFileBytes(f.uri);
        await localFile.writeAsBytes(bytes);
        copied++;
      } catch (e) {
        debugPrint('Błąd kopiowania ${f.name}: $e');
        errors++;
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Skopiowano $copied nowych, pominięto $skipped istniejących'
          '${errors > 0 ? ", błędy: $errors" : ""}',
        ),
      ),
    );

    // Jeśli bank aktywny — skanuj
    if (bank == _activeBank) {
      await _scanFolder(localDir);
    }
  }

  /// Usuwa URI folderu źródłowego banku (pliki lokalne zostają).
  Future<void> _clearBankUri(String bank) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Usunąć folder źródłowy banku "$bank"?'),
        content: const Text(
            'Pliki lokalne zostaną. Usunięty zostanie tylko link do Dysku Google.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Usuń link'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    _bankUris.remove(bank);
    await PrefService.saveBankUri(bank, null);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Usunięto link do folderu źródłowego "$bank"')),
    );
  }

  /// Przełącza aktywny bank — ładuje playlisty/oznaczenia, skanuje katalog.
  Future<void> _switchBank(String bank) async {
    if (bank == _activeBank) return;
    setState(() {
      _previousBank = _activeBank;
      _activeBank = bank;
      _activePlaylistId = null;
      _searchController.clear();
      _playlists = [];
      _playedByPlaylist = {};
      _files = [];
      _filteredFiles = [];
      _buildMode = false;
      _editingPlaylist = null;
      _selectedFileNames = [];
      _playlistNameController.text = '';
    });
    await PrefService.saveActiveBank(bank);
    _playlists = await PrefService.loadPlaylists(bank);
    _playedByPlaylist = await PrefService.loadPlayed(bank);
    final dir = await _defaultAppDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _folderPath = dir.path;
    await _scanFolder(dir);
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
        final aName = a.path.split('/').last;
        final bName = b.path.split('/').last;
        // Sortowanie numeryczne: 1, 2, 3, ..., 10, 11, ..., 96
        final aMatch = RegExp(r'^(\d+)').firstMatch(aName);
        final bMatch = RegExp(r'^(\d+)').firstMatch(bName);
        final aNum =
            aMatch != null ? int.tryParse(aMatch.group(1)!) ?? 9999 : 9999;
        final bNum =
            bMatch != null ? int.tryParse(bMatch.group(1)!) ?? 9999 : 9999;
        if (aNum != bNum) return aNum.compareTo(bNum);
        return aName.toLowerCase().compareTo(bName.toLowerCase());
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
      await PrefService.savePlayed(_activeBank, _playedByPlaylist);
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
    await PrefService.savePlaylists(_activeBank, _playlists);
    await PrefService.savePlayed(_activeBank, _playedByPlaylist);

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
      await PrefService.savePlaylists(_activeBank, _playlists);
      await PrefService.savePlayed(_activeBank, _playedByPlaylist);

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
    await PrefService.savePlaylists(_activeBank, _playlists);
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
    await PrefService.savePlayed(_activeBank, _playedByPlaylist);
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
      await PrefService.savePlaylists(_activeBank, _playlists);
      await PrefService.savePlayed(_activeBank, _playedByPlaylist);
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
                          _buildBankBar(),
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
          if (_previousBank != null) ...[
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () => _switchBank(_previousBank!),
              icon: const Icon(Icons.arrow_back, color: Colors.redAccent),
              label: const Text('Wroc do poprzedniego banku',
                  style: TextStyle(color: Colors.redAccent, fontSize: 16)),
            ),
          ],
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
          if (_previousBank != null) ...[
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () => _switchBank(_previousBank!),
              icon: const Icon(Icons.arrow_back, color: Colors.redAccent),
              label: const Text('Wroc do poprzedniego banku',
                  style: TextStyle(color: Colors.redAccent, fontSize: 16)),
            ),
          ],
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

  /// Poziomy pasek z bankami (chipsy) + przycisk dodania nowego.
  Widget _buildBankBar() {
    debugPrint('DEBUG _buildBankBar: _banks=$_banks, _activeBank=$_activeBank');
    return Container(
      height: 96,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: AppColors.topBar.withValues(alpha: 0.85),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _banks.length + 1,
        itemBuilder: (context, index) {
          // Ostatni element — przycisk "Nowy bank"
          if (index == _banks.length) {
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                avatar: const Icon(Icons.add, size: 32),
                label: const Text('Nowy', style: TextStyle(fontSize: 22)),
                onPressed: _askForNewBank,
              ),
            );
          }
          final bank = _banks[index];
          final active = bank == _activeBank;
          return Padding(
            key: ValueKey('bank_$bank'),   // ← KLUCZ dla ListView (bez indexu!)
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onLongPress: () => _showBankMenu(bank),
              child: ChoiceChip(
                key: ValueKey('chip_$bank'),       // ← KLUCZ dla chipa
                label: Text(bank, style: const TextStyle(fontSize: 22)),
                selected: active,
                onSelected: (_) => _switchBank(bank),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Dialog: tworzy nowy bank (katalog) i przełącza na niego.
  Future<void> _askForNewBank() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nowy bank'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'np. szanty, kapela1, kapela inni',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () {
              final n = ctrl.text.trim();
              if (n.isEmpty) return;
              Navigator.pop(ctx, n);
            },
            child: const Text('Utwórz'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    if (_banks.contains(name)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bank "$name" już istnieje')),
      );
      await _switchBank(name);
      return;
    }

    setState(() {
      _banks.add(name);
    });
    await PrefService.saveBanks(_banks);

    // Utwórz katalog
    final docs = await _defaultAppDir(); // używamy katalogu aktywnego banku
    final newDir = Directory('${docs.parent.path}/$name');
    if (!await newDir.exists()) {
      await newDir.create(recursive: true);
    }

    await _switchBank(name);
  }

  /// Menu banku po długim przytrzymaniu chipa.
  Future<void> _showBankMenu(String bank) async {
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
                'Bank: $bank',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Przełącz na ten bank'),
              onTap: () => Navigator.pop(ctx, 'switch'),
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Zmień nazwę'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                _bankUris[bank] == null
                    ? Icons.folder_open
                    : Icons.cloud_done,
                color: _bankUris[bank] == null ? null : Colors.green,
              ),
              title: Text(
                _bankUris[bank] == null
                    ? 'Wskaż folder źródłowy (Dysk Google)'
                    : 'Zmień folder źródłowy',
              ),
              subtitle: _bankUris[bank] == null
                  ? null
                  : Text(
                      'Folder wskazany',
                      style: const TextStyle(fontSize: 12),
                    ),
              onTap: () => Navigator.pop(ctx, 'set_uri'),
            ),
            if (_bankUris[bank] != null)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Odśwież z Dysku Google'),
                subtitle: const Text(
                  'Pobierz nowe pliki, pomiń istniejące',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, 'refresh'),
              ),
            if (_bankUris[bank] != null)
              ListTile(
                leading: const Icon(Icons.link_off),
                title: const Text('Usuń folder źródłowy'),
                onTap: () => Navigator.pop(ctx, 'clear_uri'),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                'Usuń bank',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'switch') {
      await _switchBank(bank);
    } else if (action == 'rename') {
      await _renameBank(bank);
    } else if (action == 'set_uri') {
      await _setBankUri(bank);
    } else if (action == 'refresh') {
      await _refreshFromBankUri(bank);
    } else if (action == 'clear_uri') {
      await _clearBankUri(bank);
    } else if (action == 'delete') {
      await _deleteBank(bank);
    }
  }

  /// Zmienia nazwę banku: katalog na dysku + klucz w PrefService.
  Future<void> _renameBank(String oldName) async {
    final ctrl = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zmień nazwę banku'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nowa nazwa'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () {
              final n = ctrl.text.trim();
              if (n.isEmpty) return;
              Navigator.pop(ctx, n);
            },
            child: const Text('Zmień'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty) return;
    if (newName == oldName) return;

    if (_banks.contains(newName)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bank "$newName" już istnieje')),
      );
      return;
    }

    // 1) Zmień nazwę katalogu
    try {
      final currentDir = await _defaultAppDir();
      final oldDir = Directory('${currentDir.parent.path}/$oldName');
      final newDir = Directory('${currentDir.parent.path}/$newName');
      if (await oldDir.exists()) {
        if (await newDir.exists()) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Katalog docelowy już istnieje')),
          );
          return;
        }
        await oldDir.rename(newDir.path);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Błąd zmiany katalogu: $e')),
      );
      return;
    }

    // 2) Przenieś playlisty i oznaczenia pod nowy klucz
    try {
      final prefs = await PrefService.loadPlaylists(oldName);
      final played = await PrefService.loadPlayed(oldName);
      await PrefService.savePlaylists(newName, prefs);
      await PrefService.savePlayed(newName, played);
      await PrefService.clearBankData(oldName);
    } catch (e) {
      debugPrint('Błąd przenoszenia danych banku: $e');
    }

    // 3) Przenieś URI (jeśli był ustawiony)
    final uri = _bankUris[oldName];
    if (uri != null) {
      _bankUris.remove(oldName);
      _bankUris[newName] = uri;
      await PrefService.saveBankUris(_bankUris);
    }

    // 4) Zaktualizuj listę banków
    setState(() {
      final idx = _banks.indexOf(oldName);
      if (idx >= 0) _banks[idx] = newName;
    });
    await PrefService.saveBanks(_banks);

    // 5) Jeśli zmieniono aktywny bank — ustaw nową nazwę i przeładuj
    if (_activeBank == oldName) {
      setState(() {
        _activeBank = newName;
      });
      await PrefService.saveActiveBank(newName);
      _playlists = await PrefService.loadPlaylists(newName);
      _playedByPlaylist = await PrefService.loadPlayed(newName);
      final dir = await _defaultAppDir();
      _folderPath = dir.path;
      await _scanFolder(dir);
    }
  }

  /// Usuwa bank (katalog + playlisty + oznaczenia).
  Future<void> _deleteBank(String bank) async {
    if (_banks.length <= 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nie można usunąć ostatniego banku')),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Usunąć bank "$bank"?'),
        content: const Text(
            'Zostaną usunięte wszystkie pliki, playlisty i oznaczenia tego banku.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Usuń', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    // Usuń katalog
    try {
      final currentDir = await _defaultAppDir();
      final bankDir = Directory('${currentDir.parent.path}/$bank');
      if (await bankDir.exists()) {
        await bankDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Błąd usuwania katalogu banku: $e');
    }

    await PrefService.clearBankData(bank);

    setState(() {
      _banks.remove(bank);
    });
    await PrefService.saveBanks(_banks);

    if (bank == _activeBank) {
      await _switchBank(_banks.first);
    }
  }

  Widget _buildTopBar(Playlist? activePlaylist) {
    return Container(
      height: 96,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: AppColors.topBar,
      child: Row(
        children: [
          if (_activePlaylistId != null)
            IconButton(
              icon: const Icon(Icons.arrow_back,
                  color: Colors.white, size: 44),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 64, minHeight: 64),
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
                            const Icon(Icons.queue_music, size: 32),
                        label: Text(
                            '${pl.name} (${pl.fileNames.length})',
                            style: const TextStyle(fontSize: 22)),
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
                  fontSize: 26,
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
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '${_filteredFiles.length}',
              style:
                  const TextStyle(color: Colors.white70, fontSize: 22),
            ),
          ),
          IconButton(
            icon: Icon(
              _searchOpen ? Icons.search_off : Icons.search,
              color: Colors.white,
              size: 44,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
            tooltip: 'Szukaj',
            onPressed: () =>
                setState(() => _searchOpen = !_searchOpen),
          ),
          if (!_buildMode && _activePlaylistId == null)
            IconButton(
              icon: const Icon(Icons.add, color: Colors.white, size: 44),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 64, minHeight: 64),
              tooltip: 'Nowa playlista',
              onPressed: _startNewPlaylist,
            ),
          if (_activePlaylistId != null && !_buildMode)
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white, size: 44),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 64, minHeight: 64),
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
                  color: Colors.white, size: 44),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 64, minHeight: 64),
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
                  color: Colors.white, size: 44),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 64, minHeight: 64),
              tooltip: 'Czyść listę',
              onPressed: _clearCurrentPlayed,
            ),
          if (_files.isNotEmpty && !_buildMode)
            IconButton(
              icon: const Icon(Icons.delete_sweep,
                  color: Colors.redAccent, size: 44),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 64, minHeight: 64),
              tooltip: 'Usuń wszystko',
              onPressed: _deleteAllFiles,
            ),
          IconButton(
            icon: const Icon(Icons.folder_open,
                color: Colors.white, size: 44),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
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
