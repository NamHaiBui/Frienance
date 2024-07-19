import 'package:flutter/material.dart';
import 'package:frontend/features/dashboard/components/list_tile/constants/category_icons.dart';
import 'package:frontend/model/expense_model.dart';

class ExpenseTile extends StatelessWidget {
  final Expense expense;
  const ExpenseTile(this.expense, {super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(expense.name),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(' \$${expense.amount.toStringAsFixed(2)}'),
              const Spacer(),
              Row(
                children: [
                  Icon(getCategoryIcon(expense.category)),
                  const SizedBox(width: 8),
                  Text(expense.date.toString()),
                ],
              ),
            ],
          )
        ],
      ),
    );
  }
}
