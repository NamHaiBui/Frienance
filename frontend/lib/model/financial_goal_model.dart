import 'package:json/json.dart';
@JsonCodable()
class FinancialGoal {
  final String id;
  final String name;
  final double targetAmount;
  final String? deadline; // Optional deadline
  double currentAmount; // Tracks the current amount saved towards the goal

  FinancialGoal({
    required this.id,
    required this.name,
    required this.targetAmount,
    this.deadline,
    this.currentAmount = 0.0, // Default to 0 if not provided
  });
}
