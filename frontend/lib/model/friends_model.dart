import 'package:json/json.dart';

@JsonCodable()
class FriendCircle {
  final List<String> friendCircleID;

  const FriendCircle({
    required this.friendCircleID,
  });
}
