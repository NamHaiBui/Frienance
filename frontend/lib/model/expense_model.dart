import 'package:json/json.dart';

@JsonCodable()
class Expense {
  final String id;
  final String name;
  final double amount;
  final String category;
  final String? description;
  final String date;
  final String? receiptUrl; // Optional URL to a photo/scan of the receipt

  Expense({
    required this.id,
    required this.name,
    required this.amount,
    required this.category,
    this.description,
    required this.date,
    this.receiptUrl,
  });
}
