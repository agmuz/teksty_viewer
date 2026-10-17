/// Bank — folder z plikami. Ma unikalne `id` (generowane raz), które NIE
/// zmienia się przy zmianie nazwy. Dzięki temu playlisty (przypisane po
/// `bankId`) pozostają powiązane z bankiem mimo zmiany nazwy.
class Bank {
  final String id;
  final String name;

  Bank({required this.id, required this.name});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
      };

  factory Bank.fromJson(Map<String, dynamic> json) => Bank(
        id: json['id'] as String,
        name: json['name'] as String,
      );

  Bank copyWith({String? name}) => Bank(
        id: id,
        name: name ?? this.name,
      );

  /// Generator ID — unikalny w skali apki.
  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().hashCode}';

  @override
  bool operator ==(Object other) =>
      other is Bank && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
