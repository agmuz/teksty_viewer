import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bank.dart';
import '../models/playlist.dart';

class PrefService {
  static const _kBanks = 'banks_v2';
  static const _kActiveBankId = 'active_bank_id_v2';
  static const _kPlaylists = 'playlists_v2';
  static const _kPlayed = 'played_v2';
  static const _kBankUris = 'bank_uris_v2';

  // ===== BANKI =====
  static Future<List<Bank>> loadBanks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kBanks);
    if (raw == null) {
      final bank = Bank(id: Bank.newId(), name: 'bank1');
      await saveBanks([bank]);
      await saveActiveBankId(bank.id);
      final list = Playlist(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: 'list1',
        bankId: bank.id,
        fileNames: [],
      );
      await savePlaylistsForBank(bank.id, [list]);
      return [bank];
    }
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Bank.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveBanks(List<Bank> banks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kBanks,
      jsonEncode(banks.map((b) => b.toJson()).toList()),
    );
  }

  static Future<String?> loadActiveBankId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kActiveBankId);
  }

  static Future<void> saveActiveBankId(String bankId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveBankId, bankId);
  }

  // ===== PLAYLISTY (per bankId) =====
  static Future<Map<String, List<Playlist>>> _loadAllPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPlaylists);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(
            k,
            (v as List)
                .map((e) =>
                    Playlist.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList(),
          ));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveAllPlaylists(
      Map<String, List<Playlist>> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kPlaylists,
      jsonEncode(all.map((k, v) =>
          MapEntry(k, v.map((p) => p.toJson()).toList()))),
    );
  }

  static Future<List<Playlist>> loadPlaylistsForBank(String bankId) async {
    final all = await _loadAllPlaylists();
    return all[bankId] ?? [];
  }

  static Future<void> savePlaylistsForBank(
      String bankId, List<Playlist> playlists) async {
    final all = await _loadAllPlaylists();
    all[bankId] = playlists;
    await _saveAllPlaylists(all);
  }

  static Future<void> clearBankPlaylists(String bankId) async {
    final all = await _loadAllPlaylists();
    all.remove(bankId);
    await _saveAllPlaylists(all);
  }

  // ===== OZNACZENIA (per bankId) =====
  static Future<Map<String, Map<String, List<String>>>> _loadAllPlayed() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPlayed);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(
            k,
            (v as Map<String, dynamic>).map(
              (k2, v2) => MapEntry(k2, (v2 as List).cast<String>()),
            ),
          ));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveAllPlayed(
      Map<String, Map<String, List<String>>> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPlayed, jsonEncode(all));
  }

  static Future<Map<String, List<String>>> loadPlayedForBank(
      String bankId) async {
    final all = await _loadAllPlayed();
    return all[bankId] ?? {};
  }

  static Future<void> savePlayedForBank(
      String bankId, Map<String, List<String>> played) async {
    final all = await _loadAllPlayed();
    all[bankId] = played;
    await _saveAllPlayed(all);
  }

  static Future<void> clearBankPlayed(String bankId) async {
    final all = await _loadAllPlayed();
    all.remove(bankId);
    await _saveAllPlayed(all);
  }

  // ===== URI BANKÓW (SAF) =====
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

  // ===== RESET STARYCH DANYCH =====
  static Future<void> resetOldData() async {
    final prefs = await SharedPreferences.getInstance();
    final reset = prefs.getBool('reset_v2_done') ?? false;
    if (reset) return;

    const oldKeys = [
      'banks',
      'active_bank',
      'playlists',
      'played',
      'bank_uris',
      'teksty_folder_path',
      'migrated_to_banks',
    ];
    for (final k in oldKeys) {
      await prefs.remove(k);
    }
    final keys = prefs.getKeys();
    for (final k in keys) {
      if (k.startsWith('playlists_') && !k.endsWith('_v2')) {
        await prefs.remove(k);
      }
      if (k.startsWith('played_') && !k.endsWith('_v2')) {
        await prefs.remove(k);
      }
    }

    await prefs.setBool('reset_v2_done', true);
  }
}
