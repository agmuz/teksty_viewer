import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playlist.dart';

class PrefService {
  static const _kPlaylists = 'playlists';
  static const _kPlayed = 'played';
  static const _kFolderPath = 'teksty_folder_path';

  static Future<List<Playlist>> loadPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPlaylists);
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

  static Future<void> savePlaylists(List<Playlist> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kPlaylists,
      jsonEncode(playlists.map((p) => p.toJson()).toList()),
    );
  }

  static Future<Map<String, List<String>>> loadPlayed() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPlayed);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, (v as List).cast<String>()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> savePlayed(Map<String, List<String>> played) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPlayed, jsonEncode(played));
  }

  static Future<String?> loadFolderPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kFolderPath);
  }

  static Future<void> saveFolderPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFolderPath, path);
  }
}
