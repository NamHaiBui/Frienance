import 'expense_model.dart';
import 'financial_goal_model.dart';
import 'group_model.dart';
import 'shared_expense_model.dart';

import 'package:json/json.dart';

@JsonCodable()
class User {
  final String id; // Unique identifier (e.g., email, UUID)
  final String name; // User's full name
  String? profilePicUrl; // Optional profile picture URL
  final String currency; // Preferred currency (e.g., 'USD', 'EUR')

  // Individual Expense Tracking
  double? budget; // Monthly budget (can be null if not set)
  List<String> expenseCategories; // Categories for expenses
  List<Expense> expenses; // History of individual expenses
  List<FinancialGoal> goals; // Optional list of savings goals

  // Group Expense Tracking
  List<Group> groups; // Groups the user is part of
  List<SharedExpense> sharedExpenses; // Shared expenses user is involved in

  User({
    required this.id,
    required this.name,
    this.profilePicUrl,
    required this.currency,
    this.budget,
    this.expenseCategories = const [],
    this.expenses = const [],
    this.goals = const [],
    this.groups = const [],
    this.sharedExpenses = const [],
  });
}
