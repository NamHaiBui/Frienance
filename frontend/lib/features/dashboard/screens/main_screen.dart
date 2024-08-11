import 'package:flutter/material.dart';
import 'package:frontend/features/dashboard/components/hero/charts/bar_chart.dart';
import 'package:frontend/features/template/dynamic_template.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  @override
  Widget build(BuildContext context) {
    return const DynamicScaffold(
      body: Column(children: [
        ExpenseBarChart()
        // Biggest Expense
        // Top Expenses List
        //
      ]),
    );
  }
}

void main() {
  runApp(
    const MaterialApp(
      home: MainScreen(),
    ),
  );
}
