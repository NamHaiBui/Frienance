import 'package:json/json.dart';

@JsonCodable()
class Group {
  final String id;
  final String name;
  List<String> members; // User IDs of group members

  Group({
    required this.id,
    required this.name,
    required this.members,
  });
}
