import 'package:json/json.dart';

@JsonCodable()
class SharedExpense {
  final String id;
  final double amount;
  final String? description;
  final String date;
  List<String> participants; // User IDs of participants who share the expense

  SharedExpense({
    required this.id,
    required this.amount,
    this.description,
    required this.date,
    required this.participants,
  });
}
