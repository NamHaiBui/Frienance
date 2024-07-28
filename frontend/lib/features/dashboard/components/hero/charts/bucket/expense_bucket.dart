import 'package:frontend/model/expense_model.dart';

class ExpenseBucket {
  final String bucketType;
  final String groupByCondition;
  final List<Expense> expenses;

  const ExpenseBucket(
      {required this.bucketType,
      required this.expenses,
      required this.groupByCondition});
  ExpenseBucket.forCategory(List<Expense> allExpenses,
      {required this.bucketType, required this.groupByCondition})
      : expenses = bucketType == 'expense_category'
            ? allExpenses
                .where((element) => element.category == groupByCondition)
                .toList()
            : allExpenses
                .where((element) =>
                    element.sharedWithUsers.contains(groupByCondition))
                .toList();

  double get totalExpenses {
    double sum = 0;
    for (final expense in expenses) {
      sum += expense.amount;
    }
    return sum;
  }
}
