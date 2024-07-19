import 'package:frontend/model/expense_model.dart';

class ExpenseBucket {
  final String category;
  final List<Expense> expenses;
  const ExpenseBucket({required this.category, required this.expenses});
  ExpenseBucket.forCategory(List<Expense> allExpenses, {required this.category})
      : expenses = allExpenses
            .where((element) => element.category == category)
            .toList();
  double get totalExpenses {
    double sum = 0;
    for (final expense in expenses) {
      sum += expense.amount;
    }
    return sum;
  }
}
