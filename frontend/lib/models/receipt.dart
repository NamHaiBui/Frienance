import 'package:json/json.dart';

@JsonCodable()
class Receipt {
  final String id;
  final String merchant;
  final double amount;
  final String date;
  final String rawText;

  Receipt({
    required this.id,
    required this.merchant,
    required this.amount,
    required this.date,
    required this.rawText,
  });
}
