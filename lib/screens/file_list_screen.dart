import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:saf/saf.dart';
import 'package:path_provider/path_provider.dart';
import '../models/bank.dart';
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
  String? _activeBankId;
  String? _previousBankId;
  List<Bank> _banks = [];
  Map<String, String> _bankUris = {};
  final Saf _saf = Saf();

  /// Aktywny bank (wyliczany z _banks + _activeBankId).
  Bank? get _activeBank {
    if (_activeBankId == null) return null;
    for (final b in _banks) {
      if (b.id == _activeBankId) return b;
    }
    return null;
  }

  /// Nazwa aktywnego banku (dla folderów na dysku).
  String get _activeBankName => _activeBank?.name ?? 'bank1';

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _playlistNameController =
      TextEditingController();

  bool _searchOpen = false;
  bool _buildMode = false;
  bool _editMode = false;
  bool _barsVisible = true;
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
    // NIE skanuj przy resume — to resetuje _filteredFiles i psuje filtr
    // z lupki (np. po powrocie z PDF).
    // Skanowanie tylko przy zmianie banku (_switchBank) i starcie (_init).
  }

  String get _currentPlayedKey => _activePlaylistId ?? _playedAllKey;

          Future<void> _init() async {
    // Krok 1: usuń stare dane (reset v2).
    await PrefService.resetOldData();

    _banks = await PrefService.loadBanks();
    _bankUris = await PrefService.loadBankUris();
    _activeBankId = await PrefService.loadActiveBankId();
    if (_activeBankId == null && _banks.isNotEmpty) {
      _activeBankId = _banks.first.id;
    }
    if (_activeBankId != null &&
        !_banks.any((b) => b.id == _activeBankId)) {
      _activeBankId = _banks.isNotEmpty ? _banks.first.id : null;
    }
    if (_activeBankId != null) {
      _playlists = await PrefService.loadPlaylistsForBank(_activeBankId!);
      _playedByPlaylist =
          await PrefService.loadPlayedForBank(_activeBankId!);
    }

    // Folder wewnętrzny apki: Documents/teksty/<nazwa banku>
    final dir = await _defaultAppDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _folderPath = dir.path;
    await _scanFolder(dir);
  }

  Future<Directory> _defaultAppDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/teksty/$_activeBankName');
  }

      
  Future<void> _importPdfs() async {
    // Zamiast FilePicker — używamy SAF (Dysk Google) i wywołujemy _setBankUri,
    // żeby bank automatycznie przyjął nazwę folderu (jeśli ma domyślną).
    if (_activeBank != null) {
      await _setBankUri(_activeBank!);
    }
  }

  /// Wskazanie folderu źródłowego (Dysk Google) dla banku + od razu kopiowanie.
  /// Nazwa banku zostaje automatycznie zmieniona na nazwę folderu z Dysku Google
  /// (jeśli bank ma nazwę domyślną bank1..bank5 albo pustą).
  Future<void> _setBankUri(Bank bank) async {
    // Zapamiętaj, czy bank MIAŁ już folder źródłowy.
    // Jeśli tak — to zmiana folderu (usuwamy stare pliki).
    final hadUriBefore = _bankUris[bank.id] != null;

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
      return;
    }

    // Wyciągnij nazwę folderu z Dysku Google
    final folderName = dir.name.trim();

    // Sprawdź czy bank ma nazwę domyślną (bank1..bank5)
    final isDefaultName = RegExp(r'^bank\d+$').hasMatch(bank.name);
    final shouldRename = folderName.isNotEmpty &&
        isDefaultName &&
        folderName != bank.name;

    Bank effectiveBank = bank;

    if (shouldRename) {
      // Nowa nazwa — sprawdź kolizje
      var newName = folderName;
      var counter = 2;
      while (_banks.any((b) => b.name == newName) &&
          newName != bank.name) {
        newName = '$folderName ($counter)';
        counter++;
      }

      try {
        // Zmień nazwę katalogu lokalnego
        final currentDir = await _defaultAppDir();
        final oldDir = Directory('${currentDir.parent.path}/${bank.name}');
        final newDir = Directory('${currentDir.parent.path}/$newName');
        if (await oldDir.exists() && !await newDir.exists()) {
          await oldDir.rename(newDir.path);
        }

        // Zaktualizuj bank W PAMIĘCI (id zostaje, name się zmienia)
        final renamedBank = bank.copyWith(name: newName);
        setState(() {
          final idx = _banks.indexWhere((b) => b.id == bank.id);
          if (idx >= 0) _banks[idx] = renamedBank;
        });
        await PrefService.saveBanks(_banks);

        // Przenieś URI (klucz = id, więc bez zmian)
        _bankUris[bank.id] = dir.uri;
        await PrefService.saveBankUris(_bankUris);

        effectiveBank = renamedBank;
      } catch (e) {
      }
    } else {
      // Nie zmieniamy nazwy — tylko zapisz URI (klucz = id)
      _bankUris[bank.id] = dir.uri;
      await PrefService.saveBankUris(_bankUris);
    }

    // Przeładuj banki z PrefService
    _banks = await PrefService.loadBanks();
    if (!mounted) return;
    setState(() {});

    // Zmiana folderu — usuń stare pliki z lokalnego katalogu banku.
    if (hadUriBefore) {
      try {
        final localDir = await _defaultAppDir();
        if (await localDir.exists()) {
          final files = await localDir.list().toList();
          var removed = 0;
          for (final f in files) {
            if (f is File) {
              try {
                await f.delete();
                removed++;
              } catch (_) {}
            }
          }
          if (mounted && removed > 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Usunięto $removed starych plików z "${effectiveBank.name}"',
                ),
              ),
            );
          }
        }
      } catch (e) {
        // ignore: avoid_print
        print('Błąd usuwania starych plików: $e');
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Wybrano folder dla "${effectiveBank.name}" — kopiuję pliki...',
        ),
      ),
    );

    await _refreshFromBankUri(effectiveBank);
  }

  /// Kopiuje nowe pliki z folderu źródłowego (Dysk Google) do lokalnego banku.
  /// Pomija pliki już istniejące lokalnie.
  Future<void> _refreshFromBankUri(Bank bank) async {
    final uri = _bankUris[bank.id];
    if (uri == null || uri.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bank "${bank.name}" nie ma wskazanego folderu źródłowego')),
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
    final localDir = Directory('${docs.path}/teksty/${bank.name}');
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
    if (bank.id == _activeBankId) {
      await _scanFolder(localDir);
    }
  }

  /// Usuwa URI folderu źródłowego banku (pliki lokalne zostają).
  Future<void> _clearBankUri(Bank bank) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Usunąć folder źródłowy banku "${bank.name}"?'),
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

    _bankUris.remove(bank.id);
    await PrefService.saveBankUris(_bankUris);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Usunięto link do folderu źródłowego "${bank.name}"')),
    );
  }

  /// Przełącza aktywny bank — ładuje playlisty/oznaczenia, skanuje katalog.
  Future<void> _switchBank(Bank bank) async {
    if (bank.id == _activeBankId) return;
    setState(() {
      _previousBankId = _activeBankId;
      _activeBankId = bank.id;
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
    await PrefService.saveActiveBankId(bank.id);
    _playlists = await PrefService.loadPlaylistsForBank(bank.id);
    _playedByPlaylist = await PrefService.loadPlayedForBank(bank.id);
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
          orElse: () => Playlist(
          id: '',
          name: '',
          bankId: '',
          fileNames: [],
        ),
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
      if (_activeBankId != null) {
        await PrefService.savePlayedForBank(
            _activeBankId!, _playedByPlaylist);
      }
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
        playlistName: pl.name,
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
      }
    }

    // wyczyść playlisty i oznaczenia
    setState(() {
      _playlists = _playlists
          .map((p) => Playlist(
                id: p.id,
                name: p.name,
                bankId: p.bankId,
                fileNames: [],
              ))
          .toList();
      _playedByPlaylist = _playedByPlaylist.map((k, v) => MapEntry(k, []));
    });
    if (_activeBankId != null) {
      await PrefService.savePlaylistsForBank(_activeBankId!, _playlists);
    }
    if (_activeBankId != null) {
      await PrefService.savePlayedForBank(
          _activeBankId!, _playedByPlaylist);
    }

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
                  bankId: p.bankId,
                  fileNames:
                      p.fileNames.where((n) => n != fileName).toList(),
                ))
            .toList();
        _playedByPlaylist = _playedByPlaylist.map(
          (k, v) => MapEntry(k, v.where((n) => n != fileName).toList()),
        );
      });
      if (_activeBankId != null) {
      await PrefService.savePlaylistsForBank(_activeBankId!, _playlists);
    }
      if (_activeBankId != null) {
        await PrefService.savePlayedForBank(
            _activeBankId!, _playedByPlaylist);
      }

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

  /// Tworzy nową listę — przypisaną do AKTYWNEGO banku.
  /// Nie pyta o bank — bank aktywny jest źródłem.
  /// Generuje nazwę `listN` i wchodzi w tryb budowania.
  Future<void> _startNewPlaylist() async {
    final bank = _activeBank;
    if (bank == null || !mounted) return;

    // Wygeneruj nazwę `listN` — unikalną w skali apki.
    int n = 1;
    while (true) {
      final candidate = 'list$n';
      bool taken = false;
      for (final b in _banks) {
        final pls = await PrefService.loadPlaylistsForBank(b.id);
        if (pls.any((p) => p.name == candidate)) {
          taken = true;
          break;
        }
      }
      if (!taken) break;
      n++;
    }
    final listName = 'list$n';

    final newList = Playlist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: listName,
      bankId: bank.id,
      fileNames: [],
    );

    // Zapisz listę do aktywnego banku.
    final existing = await PrefService.loadPlaylistsForBank(bank.id);
    existing.add(newList);
    await PrefService.savePlaylistsForBank(bank.id, existing);

    // Wejdź w tryb budowania tej listy.
    setState(() {
      _buildMode = true;
      _editingPlaylist = newList;
      _selectedFileNames = [];
      _playlistNameController.text = listName;
      _activePlaylistId = null;
      _playlists = [..._playlists, newList];
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

  /// Usuwa plik z zaznaczonych (long-press w _editMode).
  Future<void> _removeFromSelection(File file) async {
    final name = file.path.split('/').last;
    final plId = _activePlaylistId;
    if (plId == null) return;
    setState(() {
      _selectedFileNames.remove(name);
      final idx = _playlists.indexWhere((p) => p.id == plId);
      if (idx >= 0) {
        final pl = _playlists[idx];
        _playlists[idx] = Playlist(
          id: pl.id,
          name: pl.name,
          bankId: pl.bankId,
          fileNames: pl.fileNames.where((n) => n != name).toList(),
        );
      }
    });
    if (_activeBankId != null) {
      await PrefService.savePlaylistsForBank(_activeBankId!, _playlists);
    }
    if (mounted) _applyFilter();
  }

  /// Przenosi kafelek w playliście z pozycji [from] na [to].
  Future<void> _moveInPlaylist(int from, int to) async {
    final plId = _activePlaylistId;
    if (plId == null) return;
    setState(() {
      final idx = _playlists.indexWhere((p) => p.id == plId);
      if (idx < 0) return;
      final pl = _playlists[idx];
      final list = List<String>.from(pl.fileNames);
      if (from < 0 || from >= list.length) return;
      if (to < 0 || to > list.length) return;
      final item = list.removeAt(from);
      list.insert(to > from ? to - 1 : to, item);
      _playlists[idx] = Playlist(
        id: pl.id,
        name: pl.name,
        bankId: pl.bankId,
        fileNames: list,
      );
    });
    if (_activeBankId != null) {
      await PrefService.savePlaylistsForBank(_activeBankId!, _playlists);
    }
    if (mounted) _applyFilter();
  }

  Future<void> _saveBuildPlaylist() async {
    // Nazwa pochodzi z _editingPlaylist (lista ma już nazwę list1/list2/...).
    // Nie ma pola tekstowego — user nie wpisuje nazwy.
    final name =
        _editingPlaylist?.name ?? _playlistNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Brak nazwy playlisty')),
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
            bankId: _editingPlaylist!.bankId,
            fileNames: List.from(_selectedFileNames),
          );
        }
      } else {
        _playlists.add(Playlist(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: name,
          bankId: _activeBankId ?? '',
          fileNames: List.from(_selectedFileNames),
        ));
      }
    });
    if (_activeBankId != null) {
      await PrefService.savePlaylistsForBank(_activeBankId!, _playlists);
    }
    if (!mounted) return;
    setState(() {
      final wasEditing = _editingPlaylist;
      _buildMode = false;
      _editingPlaylist = null;
      _selectedFileNames = [];
      _playlistNameController.text = '';
      // Po zapisie — wejdź do widoku playlisty (nie do banku).
      if (wasEditing != null) {
        _activePlaylistId = wasEditing.id;
      }
      _applyFilter();
    });
  }

  void _openPlaylist(Playlist pl) {
    setState(() {
      _searchController.clear();
      // Pusta lista → od razu tryb budowania (zaznaczanie kafelków).
      if (pl.fileNames.isEmpty) {
        _activePlaylistId = null;
        _buildMode = true;
        _editingPlaylist = pl;
        _selectedFileNames = [];
        _playlistNameController.text = pl.name;
        _editMode = false;
      } else {
        // Niepusta lista → widok playlisty.
        _activePlaylistId = pl.id;
        _editMode = false;
      }
      _applyFilter();
    });
  }

  void _closePlaylist() {
    setState(() {
      _activePlaylistId = null;
      _editMode = false;
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
              leading: const Icon(Icons.swap_vert),
              title: const Text('Zmień kolejność plików'),
              onTap: () => Navigator.pop(ctx, 'reorder'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Zmień nazwę'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('Wygeneruj PDF'),
              onTap: () => Navigator.pop(ctx, 'pdf'),
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
    if (action == 'open') {
      _openPlaylist(pl);
    } else if (action == 'edit') {
      _startEditPlaylist(pl);
    } else if (action == 'rename') {
      await _renamePlaylist(pl);
    } else if (action == 'pdf') {
      await _generatePlaylistPdf(pl);
    } else if (action == 'reorder') {
      setState(() {
        _activePlaylistId = pl.id;
        _editMode = true;
        _searchController.clear();
        _applyFilter();
      });
    } else if (action == 'clear') {
      await _clearPlayed(pl.id);
    } else if (action == 'delete') {
      await _deletePlaylist(pl);
    }
  }

  Future<void> _clearPlayed(String key) async {
    setState(() => _playedByPlaylist[key] = []);
    if (_activeBankId != null) {
      await PrefService.savePlayedForBank(
          _activeBankId!, _playedByPlaylist);
    }
  }

  /// Zmienia nazwę playlisty (przez dialog).
  Future<void> _renamePlaylist(Playlist pl) async {
    final ctrl = TextEditingController(text: pl.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zmień nazwę playlisty'),
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
    if (newName == pl.name) return;

    setState(() {
      final idx = _playlists.indexWhere((p) => p.id == pl.id);
      if (idx >= 0) {
        _playlists[idx] = Playlist(
          id: pl.id,
          name: newName,
          bankId: pl.bankId,
          fileNames: List.from(pl.fileNames),
        );
      }
    });
    if (_activeBankId != null) {
      await PrefService.savePlaylistsForBank(_activeBankId!, _playlists);
    }
    if (mounted) _applyFilter();
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
      if (_activeBankId != null) {
      await PrefService.savePlaylistsForBank(_activeBankId!, _playlists);
    }
      if (_activeBankId != null) {
        await PrefService.savePlayedForBank(
            _activeBankId!, _playedByPlaylist);
      }
    }
  }

  /// Czy aktywna playlista ma oznaczenia (piaskowe kafelki).
  bool get _hasPlayedInCurrent =>
      (_playedByPlaylist[_currentPlayedKey] ?? []).isNotEmpty;

  /// Czyści oznaczenia dla aktywnej playlisty (lub wszystkich).
  Future<void> _clearCurrentPlayed() async {
    await _clearPlayed(_currentPlayedKey);
  }

  int? _selectionOrder(String fileName) {
    final idx = _selectedFileNames.indexOf(fileName);
    return idx >= 0 ? idx + 1 : null;
  }

  bool _isPlayed(String fileName) =>
      (_playedByPlaylist[_currentPlayedKey] ?? []).contains(fileName);

  @override
  Widget build(BuildContext context) {
    final activePlaylist = _activePlaylistId != null
        ? _playlists.firstWhere(
            (p) => p.id == _activePlaylistId,
            orElse: () => Playlist(
          id: '',
          name: '',
          bankId: '',
          fileNames: [],
        ),
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
                    : Stack(
                        children: [
                          // Kafelki — na WIERZCHU (scroll się tu dzieje).
                          Positioned.fill(
                            child:
                                NotificationListener<ScrollNotification>(
                              onNotification: (n) {
                                if (n is ScrollUpdateNotification) {
                                  final offset = n.metrics.pixels;
                                  if (offset > 0 && _barsVisible) {
                                    setState(() => _barsVisible = false);
                                  } else if (offset == 0 && !_barsVisible) {
                                    setState(() => _barsVisible = true);
                                  }
                                }
                                return false;
                              },
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final isLandscape =
                                      constraints.maxWidth >
                                          constraints.maxHeight;
                                  final cols = isLandscape ? 4 : 2;
                                  // 16 wierszy w pionie, 8 w poziomie.
                                  final rows = isLandscape ? 8 : 16;
                                  // Wysokość kafelka z DOSTĘPNEJ wysokości
                                  // grida (po odjęciu pasków 2 * tileH).
                                  final tileH =
                                      constraints.maxHeight / (rows + 2);
                                  // Wysokość pasków (topBar 96 + bankBar 96
                                  // w widoku banku; w widoku playlisty tylko
                                  // topBar 96).
                                  // Paski: topBar (96) + bankBar (96)
                                  // + margines (8) = 200. Gdy search
                                  // otwarty — bankBar wyższy o ~60 px
                                  // (TextField) = 260.
                                  final barsHeight = _activePlaylistId == null
                                      ? (_searchOpen ? 260.0 : 200.0)
                                      : (_searchOpen ? 160.0 : 96.0);
                                  return GridView.builder(
                                    padding: EdgeInsets.only(
                                      left: 4,
                                      right: 4,
                                      bottom: 4,
                                      top: _barsVisible
                                          ? barsHeight + 6
                                          : 6,
                                    ),
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: cols,
                                      crossAxisSpacing: 6,
                                      mainAxisSpacing: 4,
                                      mainAxisExtent: tileH,
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
                                        orderNumber:
                                            _selectionOrder(fileName),
                                        tileHeight: tileH,
                                        editMode: _editMode,
                                        index: index,
                                        position:
                                            _editMode ? index + 1 : null,
                                        onMove: _moveInPlaylist,
                                        onTap: () {
                                          if (_buildMode) {
                                            _toggleSelection(file);
                                          } else if (_editMode) {
                                            // w edycji: nic
                                          } else {
                                            _openPdf(file, index: index);
                                          }
                                        },
                                        onLongPress: () {
                                          if (_editMode) {
                                            _removeFromSelection(file);
                                          } else if (_activePlaylistId !=
                                              null) {
                                            // długie w playliście — nic
                                          } else {
                                            _deleteFile(file);
                                          }
                                        },
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                          // Paski — na SPODZIE (animowane).
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                            top: _barsVisible
                                ? 0
                                : -(_activePlaylistId == null
                                    ? 200.0
                                    : 96.0),
                            left: 0,
                            right: 0,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildTopBar(activePlaylist),
                                if (_activePlaylistId == null) _buildBankBar(),
                              ],
                            ),
                          ),
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
          if (_previousBankId != null) ...[
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () => _switchBank(_banks.firstWhere(
                  (b) => b.id == _previousBankId,
                  orElse: () => _banks.first,
                )),
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
          if (_previousBankId != null) ...[
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () => _switchBank(_banks.firstWhere(
                  (b) => b.id == _previousBankId,
                  orElse: () => _banks.first,
                )),
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
    return Container(
      color: AppColors.topBar.withValues(alpha: 0.85),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Szukaj po tytule...',
          hintStyle: const TextStyle(color: Colors.white54),
          prefixIcon: const Icon(Icons.search, color: Colors.white, size: 20),
          suffixIcon: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            onPressed: () {
              _searchController.clear();
              setState(() => _searchOpen = false);
            },
          ),
          border: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white54),
          ),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white54),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white),
          ),
          isDense: true,
        ),
      ),
    );
  }

  /// Poziomy pasek z bankami (chipsy) + przycisk dodania nowego.
  Widget _buildBankBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: AppColors.topBar.withValues(alpha: 0.85),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 96,
            child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _banks.length + 1,
              itemBuilder: (context, index) {
                // Pierwszy element — chip "+ Banki" (nowy bank).
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      label: const Text('+ Banki',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.black)),
                      backgroundColor: AppColors.tilePlayed,
                      tooltip: 'Nowy bank',
                      onPressed: _askForNewBank,
                    ),
                  );
                }
                final bank = _banks[index - 1];
                final active = bank.id == _activeBankId;
                return Padding(
                  key: ValueKey('bank_${bank.id}'),
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onLongPress: () => _showBankMenu(bank),
                    child: ChoiceChip(
                      key: ValueKey('chip_${bank.id}'),
                      label: Text(bank.name,
                          style: const TextStyle(fontSize: 22)),
                      selected: active,
                      onSelected: (_) => _switchBank(bank),
                    ),
                  ),
                );
              },
            ),
          ),
          // Licznik plików.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '${_filteredFiles.length}',
              style: const TextStyle(
                  color: Colors.white70, fontSize: 22),
            ),
          ),
          // Miotełka — czyść oznaczenia (tylko gdy są oznaczenia).
          if (_hasPlayedInCurrent)
            IconButton(
              icon: const Icon(
                Icons.cleaning_services,
                color: Colors.white,
                size: 32,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              tooltip: 'Czyść oznaczenia',
              onPressed: _clearCurrentPlayed,
            ),
          // Lupka (szukaj).
          IconButton(
            icon: Icon(
              _searchOpen ? Icons.search_off : Icons.search,
              color: Colors.white,
              size: 32,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            tooltip: 'Szukaj',
            onPressed: () =>
                setState(() => _searchOpen = !_searchOpen),
          ),
        ],
      ),
          ),
          // Wiersz 2 — pole wyszukiwania (gdy _searchOpen).
          if (_searchOpen) _buildSearchField(),
        ],
      ),
    );
  }

  /// Dialog: tworzy nowy bank (katalog) i przełącza na niego.
  /// Nowy bank — bez dialogu, od razu SAF (wybór folderu).
  /// Nazwa banku = nazwa wybranego folderu (z kolizją `folder (2)`).
  Future<void> _askForNewBank() async {
    // 1) Wybierz folder przez SAF.
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
    if (dir == null) return;

    // 2) Nazwa banku = nazwa folderu.
    final rawName = dir.name.trim();
    if (rawName.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Folder bez nazwy')),
      );
      return;
    }

    // 3) Kolizja nazw — dopisz (2), (3), ...
    var bankName = rawName;
    var counter = 2;
    while (_banks.any((b) => b.name == bankName)) {
      bankName = '$rawName ($counter)';
      counter++;
    }

    // 4) Nowy Bank + zapis URI + katalog lokalny.
    final newBank = Bank(id: Bank.newId(), name: bankName);
    setState(() {
      _banks.add(newBank);
    });
    await PrefService.saveBanks(_banks);

    _bankUris[newBank.id] = dir.uri;
    await PrefService.saveBankUris(_bankUris);

    final docs = await _defaultAppDir();
    final newDir = Directory('${docs.parent.path}/$bankName');
    if (!await newDir.exists()) {
      await newDir.create(recursive: true);
    }

    // 5) Przełącz na nowy bank i skopiuj pliki z Dysku.
    await _switchBank(newBank);
    await _refreshFromBankUri(newBank);
  }

  /// Menu banku po długim przytrzymaniu chipa.
  Future<void> _showBankMenu(Bank bank) async {
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
                'Bank: ${bank.name}',
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
                _bankUris[bank.id] == null
                    ? Icons.folder_open
                    : Icons.cloud_done,
                color: _bankUris[bank.id] == null ? null : Colors.green,
              ),
              title: Text(
                _bankUris[bank.id] == null
                    ? 'Wskaż folder źródłowy (Dysk Google)'
                    : 'Zmień folder źródłowy',
              ),
              subtitle: _bankUris[bank.id] == null
                  ? null
                  : const Text(
                      'Folder wskazany',
                      style: TextStyle(fontSize: 12),
                    ),
              onTap: () => Navigator.pop(ctx, 'set_uri'),
            ),
            if (_bankUris[bank.id] != null)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Odśwież z Dysk Google'),
                subtitle: const Text(
                  'Pobierz nowe pliki, pomiń istniejące',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, 'refresh'),
              ),
            if (_bankUris[bank.id] != null)
              ListTile(
                leading: const Icon(Icons.link_off),
                title: const Text('Usuń folder źródłowy'),
                onTap: () => Navigator.pop(ctx, 'clear_uri'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_sweep,
                  color: Colors.redAccent),
              title: const Text('Usuń wszystkie pliki'),
              onTap: () => Navigator.pop(ctx, 'delete_all'),
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
    } else if (action == 'delete_all') {
      await _deleteAllFiles();
    } else if (action == 'delete') {
      await _deleteBank(bank);
    }
  }

  /// Zmienia nazwę banku: katalog na dysku + nazwę w modelu Bank.
  /// `id` banku NIE zmienia się — więc playlisty (po bankId) zostają.
  Future<void> _renameBank(Bank bank) async {
    final ctrl = TextEditingController(text: bank.name);
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
    if (newName == bank.name) return;

    if (_banks.any((b) => b.name == newName)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bank "$newName" już istnieje')),
      );
      return;
    }

    // 1) Zmień nazwę katalogu
    try {
      final currentDir = await _defaultAppDir();
      final oldDir = Directory('${currentDir.parent.path}/${bank.name}');
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

    // 2) Zaktualizuj bank w pamięci (id zostaje)
    setState(() {
      final idx = _banks.indexWhere((b) => b.id == bank.id);
      if (idx >= 0) _banks[idx] = bank.copyWith(name: newName);
    });
    await PrefService.saveBanks(_banks);

    // 3) Jeśli zmieniono aktywny bank — przeładuj
    if (_activeBankId == bank.id) {
      final dir = await _defaultAppDir();
      _folderPath = dir.path;
      await _scanFolder(dir);
    }
  }

  /// Usuwa bank (katalog + playlisty + oznaczenia).
  Future<void> _deleteBank(Bank bank) async {
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
        title: Text('Usunąć bank "${bank.name}"?'),
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
      final bankDir = Directory('${currentDir.parent.path}/${bank.name}');
      if (await bankDir.exists()) {
        await bankDir.delete(recursive: true);
      }
    } catch (e) {
    }

    await PrefService.clearBankPlaylists(bank.id);
    await PrefService.clearBankPlayed(bank.id);
    _bankUris.remove(bank.id);
    await PrefService.saveBankUris(_bankUris);

    setState(() {
      _banks.removeWhere((b) => b.id == bank.id);
    });
    await PrefService.saveBanks(_banks);

    if (bank.id == _activeBankId) {
      if (_banks.isNotEmpty) {
        await _switchBank(_banks.first);
      }
    }
  }

  Widget _buildTopBar(Playlist? activePlaylist) {
    return Container(
      height: 96,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: AppColors.topBar,
      child: Row(
        children: [
          if (_activePlaylistId == null)
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  // Chip "+ Listy" — nowa lista (po lewej).
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      label: const Text('+ Listy',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.black)),
                      backgroundColor: AppColors.tilePlayed,
                      tooltip: 'Nowa lista',
                      onPressed: _startNewPlaylist,
                    ),
                  ),
                  // Chipy list.
                  for (final pl in _playlists)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onLongPress: () => _showPlaylistMenu(pl),
                        child: Builder(builder: (context) {
                          // Licznik na bieżąco: w trybie budowania tej
                          // listy pokazujemy liczbę zaznaczonych kafelków.
                          final isEditing = _buildMode &&
                              _editingPlaylist?.id == pl.id;
                          final count = isEditing
                              ? _selectedFileNames.length
                              : pl.fileNames.length;
                          return ActionChip(
                            label: Text(
                                '${pl.name} ($count)',
                                style: const TextStyle(fontSize: 22)),
                            onPressed: () async {
                              if (isEditing) {
                                await _saveBuildPlaylist();
                                return;
                              }
                              _openPlaylist(pl);
                            },
                          );
                        }),
                      ),
                    ),
                ],
              ),
            )
          else if (_activePlaylistId != null)
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onLongPress: () {
                    if (activePlaylist != null) {
                      _showPlaylistMenu(activePlaylist);
                    }
                  },
                  child: ActionChip(
                    label: Text(
                      '${activePlaylist?.name ?? ""} (${activePlaylist?.fileNames.length ?? 0})',
                      style: const TextStyle(fontSize: 22),
                    ),
                    onPressed: () {
                      if (_editMode) {
                        setState(() {
                          _editMode = false;
                          _applyFilter();
                        });
                      } else {
                        _closePlaylist();
                      }
                    },
                  ),
                ),
              ),
            ),
          if (_activePlaylistId != null && _hasPlayedInCurrent && !_editMode)
            IconButton(
              icon: const Icon(
                Icons.cleaning_services,
                color: Colors.white,
                size: 32,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              tooltip: 'Czyść oznaczenia',
              onPressed: _clearCurrentPlayed,
            ),
        ],
      ),
    );
  }


}
