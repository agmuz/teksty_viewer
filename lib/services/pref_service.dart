import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playlist.dart';

class PrefService {
  // ===== BANKI =====
  static const _kBanks = 'banks';
  static const _kActiveBank = 'active_bank';

  /// Domyślne banki przy pierwszym uruchomieniu.
  static const List<String> defaultBanks = [
    'bank1',
    'bank2',
    'bank3',
    'bank4',
    'bank5',
  ];

  static Future<List<String>> loadBanks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kBanks);
    if (raw == null) {
      // Pierwsze uruchomienie — ustaw domyślne banki
      await saveBanks(defaultBanks);
      return List<String>.from(defaultBanks);
    }
    try {
      final list = jsonDecode(raw) as List;
      return list.cast<String>();
    } catch (_) {
      return List<String>.from(defaultBanks);
    }
  }

  static Future<void> saveBanks(List<String> banks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBanks, jsonEncode(banks));
  }

  static Future<String> loadActiveBank() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kActiveBank) ?? defaultBanks.first;
  }

  static Future<void> saveActiveBank(String bank) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveBank, bank);
  }

  // ===== PLAYLISTY (per bank) =====
  static String _playlistsKey(String bank) => 'playlists_$bank';
  static String _playedKey(String bank) => 'played_$bank';

  static Future<List<Playlist>> loadPlaylists(String bank) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playlistsKey(bank));
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Playlist.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> savePlaylists(String bank, List<Playlist> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _playlistsKey(bank),
      jsonEncode(playlists.map((p) => p.toJson()).toList()),
    );
  }

  static Future<Map<String, List<String>>> loadPlayed(String bank) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playedKey(bank));
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, (v as List).cast<String>()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> savePlayed(String bank, Map<String, List<String>> played) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playedKey(bank), jsonEncode(played));
  }

  /// Usuwa playlisty i oznaczenia danego banku.
  static Future<void> clearBankData(String bank) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_playlistsKey(bank));
    await prefs.remove(_playedKey(bank));
  }

  // ===== STARE KLUCZE (migracja) =====
  static const _kOldPlaylists = 'playlists';
  static const _kOldPlayed = 'played';
  static const _kOldFolderPath = 'teksty_folder_path';

  /// Migracja ze starych kluczy (bez banku) do banku "kapela1".
  /// Wywołaj raz przy starcie.
  static Future<void> migrateIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final migrated = prefs.getBool('migrated_to_banks') ?? false;
    if (migrated) return;

    final oldPl = prefs.getString(_kOldPlaylists);
    final oldPlayed = prefs.getString(_kOldPlayed);
    if (oldPl != null) {
      await prefs.setString('playlists_kapela1', oldPl);
      await prefs.remove(_kOldPlaylists);
    }
    if (oldPlayed != null) {
      await prefs.setString('played_kapela1', oldPlayed);
      await prefs.remove(_kOldPlayed);
    }
    await prefs.setBool('migrated_to_banks', true);
  }

  // ===== FOLDER (już nieużywane do trzymania ścieżki, ale zostawiamy) =====
  static Future<String?> loadFolderPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kOldFolderPath);
  }

  static Future<void> saveFolderPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOldFolderPath, path);
  }

  // ===== URI BANKÓW (SAF - Dysk Google) =====
  static const _kBankUris = 'bank_uris';

  /// Zwraca mapę bank -> URI folderu na Dysku Google.
  static Future<Map<String, String>> loadBankUris() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kBankUris);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveBankUris(Map<String, String> uris) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBankUris, jsonEncode(uris));
  }

  /// Zwraca URI folderu dla danego banku (albo null jeśli nie ustawiono).
  static Future<String?> loadBankUri(String bank) async {
    final uris = await loadBankUris();
    return uris[bank];
  }

  static Future<void> saveBankUri(String bank, String? uri) async {
    final uris = await loadBankUris();
    if (uri == null || uri.isEmpty) {
      uris.remove(bank);
    } else {
      uris[bank] = uri;
    }
    await saveBankUris(uris);
  }

}
