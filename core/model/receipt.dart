import 'package:json/json.dart';

@JsonCodable()
class Receipt {
  final String url;
  final String? storeName;
  final String? date;
  final List<String> associatedExpense;
  final double total;
  const Receipt({
    required this.url,
    this.storeName,
    this.date,
    required this.total,
    required this.associatedExpense,
  });
}
