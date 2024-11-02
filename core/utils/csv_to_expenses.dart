import 'dart:io';
import 'package:csv/csv.dart';
import 'package:frontend/model/expense_model.dart';

class ExpenseCsvParser {
  Future<List<Expense>> parseExpensesFromCsv(String filePath) async {
    final file = File(filePath);
    final contents = await file.readAsString();
    final List<List<dynamic>> rowsAsListOfValues =
        const CsvToListConverter().convert(contents);

    // Assuming the first row contains headers
    final headers = rowsAsListOfValues[0];
    final dataRows = rowsAsListOfValues.sublist(1);

    return dataRows.map((row) => _createExpenseFromRow(headers, row)).toList();
  }

  Expense _createExpenseFromRow(List<dynamic> headers, List<dynamic> row) {
    final Map<String, dynamic> expenseMap = {};

    for (int i = 0; i < headers.length; i++) {
      expenseMap[headers[i].toString().toLowerCase()] = row[i];
    }

    return Expense(
      id: expenseMap['id'],
      name: expenseMap['name'],
      amount: double.parse(expenseMap['amount'].toString()),
      category: expenseMap['category'],
      description: expenseMap['description'],
      date: expenseMap['date'],
      receiptUrl: expenseMap['receipturl'],
      sharedWithUsers: _parseSharedUsers(expenseMap['sharedwithusers']),
    );
  }

  List<UserId> _parseSharedUsers(String sharedUsersString) {
    if (sharedUsersString.isEmpty) return [];
    return sharedUsersString.split(',').map((userId) => userId.trim()).toList();
  }
}
