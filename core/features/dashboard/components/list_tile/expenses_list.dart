import 'package:flutter/material.dart';
import 'package:frontend/features/dashboard/components/list_tile/expense_tile.dart';
import 'package:frontend/model/expense_model.dart';

class ExpensesList extends StatelessWidget {
  final List<Expense> expenses;
  final void Function(Expense expense) onDelete;
  const ExpensesList(
      {super.key, required this.expenses, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
        child: ListView.builder(
      scrollDirection: Axis.vertical,
      shrinkWrap: true,
      itemBuilder: (ctx, index) => Dismissible(
        key: ValueKey(expenses[index].id),
        background: Container(
            color: Theme.of(context).colorScheme.error,
            margin: EdgeInsets.symmetric(
                horizontal: Theme.of(context).cardTheme.margin!.horizontal)),
        child: ExpenseTile(expenses[index]),
        onDismissed: (direction) {
          onDelete(expenses[index]);
        },
      ),
      itemCount: expenses.length,
    ));
  }
}
