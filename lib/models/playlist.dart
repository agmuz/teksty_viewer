import 'dart:convert';

/// Playlist — lista utworów przypisana do JEDNEGO banku (po `bankId`).
class Playlist {
  final String id;
  final String name;
  final String bankId;
  final List<String> fileNames;

  Playlist({
    required this.id,
    required this.name,
    required this.bankId,
    required this.fileNames,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bankId': bankId,
        'fileNames': fileNames,
      };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String,
        name: json['name'] as String,
        bankId: json['bankId'] as String? ?? '',
        fileNames:
            (json['fileNames'] as List?)?.cast<String>() ?? <String>[],
      );

  Playlist copyWith({
    String? name,
    String? bankId,
    List<String>? fileNames,
  }) =>
      Playlist(
        id: id,
        name: name ?? this.name,
        bankId: bankId ?? this.bankId,
        fileNames: fileNames ?? this.fileNames,
      );

  String encode() => jsonEncode(toJson());
  static Playlist decode(String raw) =>
      Playlist.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
