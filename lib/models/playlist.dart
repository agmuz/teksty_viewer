import 'dart:convert';

class Playlist {
  final String id;
  final String name;
  final List<String> fileNames;

  Playlist({required this.id, required this.name, required this.fileNames});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'fileNames': fileNames,
      };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String,
        name: json['name'] as String,
        fileNames: (json['fileNames'] as List).cast<String>(),
      );

  String encode() => jsonEncode(toJson());
  static Playlist decode(String raw) =>
      Playlist.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
